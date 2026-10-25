package com.localfit.localfit_ai

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "localfit/steps"
    private val scaleChannelName = "localfit/scale"

    private val handler = Handler(Looper.getMainLooper())

    /**
     * 正在等传感器事件的一次 read。事件、超时、注册失败三条路径都会来抢答，
     * replied 保证 Result 只被完成一次（第二次答复会抛异常）。
     */
    private var pendingRead: PendingRead? = null

    /** 正在等系统权限对话框的 requestPermission 调用（同一时刻至多一个）。 */
    private var pendingPermissionResult: MethodChannel.Result? = null

    /** 正在等的秤同步窗口（扫描 + 连接 + 读一次，同一时刻至多一个）。 */
    private var pendingScale: PendingScaleRead? = null

    /** 正在等蓝牙权限对话框的秤侧 requestPermission 调用。 */
    private var pendingScalePermissionResult: MethodChannel.Result? = null

    private inner class PendingRead(
        private val result: MethodChannel.Result,
        private val sensorManager: SensorManager,
    ) {

        var replied = false

        val listener: SensorEventListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (event.sensor.type != Sensor.TYPE_STEP_COUNTER) return
                finish(
                    mapOf(
                        "status" to "ok",
                        "counter" to event.values[0].toInt(),
                        "atMs" to System.currentTimeMillis(),
                    ),
                )
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        private val timeout = Runnable {
            finish(mapOf("status" to "unavailable", "reason" to "no_event"))
        }

        fun start() {
            handler.postDelayed(timeout, READ_TIMEOUT_MS)
        }

        /** 收尾这次 read：先解注册再答复，传感器不留到下一次读取之后。 */
        fun finish(payload: Map<String, Any?>) {
            if (replied) return
            replied = true
            handler.removeCallbacks(timeout)
            sensorManager.unregisterListener(listener)
            if (pendingRead === this) pendingRead = null
            result.success(payload)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> readSteps(result)
                    "requestPermission" -> requestStepPermission(result)
                    "openAppSettings" -> openAppSettings(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, scaleChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "check" -> checkScale(result)
                    "requestPermission" -> requestScalePermission(result)
                    "scanOnce" -> scanScaleOnce(result)
                    "openAppSettings" -> openAppSettings(result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        // 配置变更/销毁时把还在等的读取摘掉：既防监听器泄漏，也不让 Dart 的
        // Future 一直挂着（引擎此刻还活着，答复可以正常送达）。
        pendingRead?.finish(mapOf("status" to "unavailable", "reason" to "no_event"))
        pendingRead = null
        // 对话框没回来 Activity 就没了，这个请求不可能再有结果，按拒绝答复。
        pendingPermissionResult?.success(mapOf("status" to "denied"))
        pendingPermissionResult = null
        pendingScale?.finish(mapOf("status" to "no_scale", "reason" to "activity_destroyed"))
        pendingScale = null
        pendingScalePermissionResult?.success(mapOf("status" to "denied"))
        pendingScalePermissionResult = null
        super.onDestroy()
    }

    private fun readSteps(result: MethodChannel.Result) {
        // 权限先于传感器检查：API 29+ 未授权就取不到计数值，而 Dart 侧的
        // 「未授权」（有「去设置」入口）与「无传感器」是两个不同的空态。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(mapOf("status" to "denied"))
            return
        }

        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val counter = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sensorManager == null || counter == null) {
            // 没有计步器就没有今日步数这一项；有 DETECTOR（只能给「有/无迈步」事件，
            // 拿不到今日总数）时如实返回 detector_only，UI 才能给出对得上的文案。
            val hasDetector = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) != null
            val reason = if (hasDetector) "detector_only" else "no_counter_sensor"
            result.success(mapOf("status" to "unavailable", "reason" to reason))
            return
        }

        // 上一次 read 的窗口还没走完就又来一次：先答旧的，避免两个监听器同时挂着。
        pendingRead?.finish(mapOf("status" to "unavailable", "reason" to "no_event"))

        val pending = PendingRead(result, sensorManager)
        pendingRead = pending
        // 一次性读取：只取首个事件，SENSOR_DELAY_NORMAL 足够（前台按需采样，不常驻后台）。
        if (!sensorManager.registerListener(
                pending.listener,
                counter,
                SensorManager.SENSOR_DELAY_NORMAL,
            )
        ) {
            pending.finish(mapOf("status" to "unavailable", "reason" to "no_event"))
            return
        }
        pending.start()
    }

    private fun requestStepPermission(result: MethodChannel.Result) {
        // API < 29 没有这项运行时权限；已授权时也不必再弹一次对话框。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(mapOf("status" to "granted"))
            return
        }

        // 上一个对话框还没回来就又来一个请求：旧请求先答 denied，
        // 否则它的 Dart Future 永远等不到结果。
        pendingPermissionResult?.success(mapOf("status" to "denied"))
        pendingPermissionResult = result

        // minSdk 24：checkSelfPermission / requestPermissions 在 Activity 上就有，
        // 够用且不必为 ActivityCompat 新增 androidx.core 依赖。
        requestPermissions(
            arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
            REQUEST_ACTIVITY_RECOGNITION,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_ACTIVITY_RECOGNITION -> {
                val pending = pendingPermissionResult ?: return
                pendingPermissionResult = null
                // 结果数组缺失/过短按拒绝答复：宁可如实说「被拒」，也不让 Result 落空。
                val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                val status = if (granted) "granted" else "denied"
                pending.success(mapOf("status" to status))
            }
            REQUEST_BLUETOOTH -> {
                val pending = pendingScalePermissionResult ?: return
                pendingScalePermissionResult = null
                // SCAN 与 CONNECT 两个都要：缺一个扫描或连接都会失败。
                val granted = grantResults.size == 2 &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                val status = if (granted) "granted" else "denied"
                pending.success(mapOf("status" to status))
            }
        }
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )
        startActivity(intent)
        result.success(null)
    }

    // ===================== 电子体重秤（docs/31 S6，需求 47 / D6） =====================
    //
    // 仅前台、用户主动同步：一次 scanOnce = 扫描（10 秒窗口）→ 连上第一个
    // 广播标准体重秤服务（0x181D）的设备 → 订阅体重测量特征（0x2A9D）通知
    // → 读一次就断开。厂商私有 GATT（小米等）不广播该服务 → 如实报 no_scale，
    // 不猜协议。**不做后台监听**（D6：那需要通知 + 前台服务整套基础设施）。

    private fun hasBluetoothPermissions(): Boolean =
        checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) ==
            PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun checkScale(result: MethodChannel.Result) {
        // D6 备注：API ≤ 30 扫描需要定位权限，本仓默认不加 —— 老设备诚实降级。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(mapOf("status" to "unsupported", "reason" to "api_too_low"))
            return
        }
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        if (manager?.adapter == null) {
            result.success(mapOf("status" to "unsupported", "reason" to "no_adapter"))
            return
        }
        if (!hasBluetoothPermissions()) {
            result.success(mapOf("status" to "denied"))
            return
        }
        result.success(mapOf("status" to "ready"))
    }

    private fun requestScalePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasBluetoothPermissions()) {
            result.success(mapOf("status" to "granted"))
            return
        }
        // 上一个对话框还没回来就又来一个请求：旧请求先答 denied。
        pendingScalePermissionResult?.success(mapOf("status" to "denied"))
        pendingScalePermissionResult = result
        requestPermissions(
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            ),
            REQUEST_BLUETOOTH,
        )
    }

    @SuppressLint("MissingPermission")
    private fun scanScaleOnce(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(mapOf("status" to "unsupported", "reason" to "api_too_low"))
            return
        }
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = manager?.adapter
        if (adapter == null) {
            result.success(mapOf("status" to "unsupported", "reason" to "no_adapter"))
            return
        }
        if (!hasBluetoothPermissions()) {
            result.success(mapOf("status" to "denied"))
            return
        }
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            // 典型原因：蓝牙没开。Dart 侧按「未发现秤」呈现并提示检查蓝牙。
            result.success(mapOf("status" to "no_scale", "reason" to "scanner_unavailable"))
            return
        }
        // 上一次窗口还没走完就又来一次：先收掉旧的（新请求取而代之）。
        pendingScale?.finish(mapOf("status" to "no_scale", "reason" to "superseded"))

        val pending = PendingScaleRead(result)
        pendingScale = pending
        pending.scanner = scanner
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(UUID_WEIGHT_SCALE_SERVICE))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            scanner.startScan(listOf(filter), settings, pending.scanCallback)
        } catch (_: Exception) {
            pending.finish(mapOf("status" to "no_scale", "reason" to "scan_start_failed"))
            return
        }
        pending.start()
    }

    /**
     * 0x2A9D Weight Measurement：flags(1B) + IEEE-11073 16-bit SFLOAT。
     * mantissa 12 bit（二补码）+ exponent 4 bit（二补码），SI 单位下 kg。
     * 返回克（整数），不把浮点解析交给 Dart。英制读数本应用不收（如实
     * 报 bad_measurement），不做 lb→kg 的悄悄换算。
     */
    private fun parseWeightGrams(data: ByteArray): Int? {
        if (data.size < 3) return null
        val flags = data[0].toInt() and 0xFF
        if (flags and 0x01 != 0) return null
        val raw = (data[1].toInt() and 0xFF) or ((data[2].toInt() and 0xFF) shl 8)
        var mantissa = raw and 0x0FFF
        if (mantissa >= 0x0800) mantissa -= 0x1000
        var exponent = (raw shr 12) and 0x0F
        if (exponent >= 0x08) exponent -= 0x10
        val kg = mantissa * Math.pow(10.0, exponent.toDouble())
        return Math.round(kg * 1000).toInt()
    }

    private inner class PendingScaleRead(
        private val result: MethodChannel.Result,
    ) {

        var replied = false
        var scanner: android.bluetooth.le.BluetoothLeScanner? = null
        var gatt: BluetoothGatt? = null
        var deviceFound = false

        private val timeout = Runnable {
            if (deviceFound) {
                finish(mapOf("status" to "timeout", "reason" to "gatt_window"))
            } else {
                finish(mapOf("status" to "no_scale", "reason" to "scan_window"))
            }
        }

        val scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                if (replied || deviceFound) return
                deviceFound = true
                stopScanning()
                try {
                    gatt = result.device.connectGatt(
                        this@MainActivity,
                        false,
                        gattCallback,
                        android.bluetooth.BluetoothDevice.TRANSPORT_LE,
                    )
                } catch (_: Exception) {
                    finish(mapOf("status" to "timeout", "reason" to "connect_failed"))
                }
            }

            override fun onScanFailed(errorCode: Int) {
                finish(mapOf("status" to "no_scale", "reason" to "scan_error_$errorCode"))
            }
        }

        val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(
                gatt: BluetoothGatt,
                status: Int,
                newState: Int,
            ) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> gatt.discoverServices()
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        if (!replied) {
                            finish(mapOf("status" to "timeout", "reason" to "gatt_disconnected"))
                        }
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (replied) return
                val service = gatt.getService(UUID_WEIGHT_SCALE_SERVICE)
                val characteristic = service?.getCharacteristic(UUID_WEIGHT_MEASUREMENT)
                if (service == null || characteristic == null) {
                    // 广播里有 0x181D 却没有测量特征：秤的实现不完整，如实上报。
                    finish(mapOf("status" to "no_scale", "reason" to "no_weight_service"))
                    return
                }
                gatt.setCharacteristicNotification(characteristic, true)
                val descriptor =
                    characteristic.getDescriptor(UUID_CLIENT_CHARACTERISTIC_CONFIG)
                if (descriptor == null) {
                    finish(mapOf("status" to "timeout", "reason" to "no_cccd"))
                    return
                }
                descriptor.value = android.bluetooth.BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                if (!gatt.writeDescriptor(descriptor)) {
                    finish(mapOf("status" to "timeout", "reason" to "cccd_write_failed"))
                }
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                if (replied) return
                if (characteristic.uuid != UUID_WEIGHT_MEASUREMENT) return
                val grams = parseWeightGrams(value)
                if (grams == null) {
                    finish(mapOf("status" to "timeout", "reason" to "bad_measurement"))
                    return
                }
                finish(
                    mapOf(
                        "status" to "ok",
                        "grams" to grams,
                        "atMs" to System.currentTimeMillis(),
                    ),
                )
            }
        }

        fun start() {
            handler.postDelayed(timeout, SCALE_TIMEOUT_MS)
        }

        fun stopScanning() {
            try {
                scanner?.stopScan(scanCallback)
            } catch (_: Exception) {
                // 蓝牙栈在我们前已经把扫描停了：不影响收尾。
            }
        }

        /** 收尾：停扫描、断 GATT、撤超时，三件事都做了才答复（且只答一次）。 */
        fun finish(payload: Map<String, Any?>) {
            if (replied) return
            replied = true
            handler.removeCallbacks(timeout)
            stopScanning()
            gatt?.let {
                try {
                    it.disconnect()
                    it.close()
                } catch (_: Exception) {
                    // GATT 已被系统回收：不影响收尾。
                }
            }
            gatt = null
            if (pendingScale === this) pendingScale = null
            // GATT 回调在 binder 线程：Result 的答复切回主线程。
            handler.post { result.success(payload) }
        }
    }

    private companion object {
        /** requestPermissions 的请求码，在本 Activity 内稳定唯一即可。 */
        const val REQUEST_ACTIVITY_RECOGNITION = 0x5711
        const val REQUEST_BLUETOOTH = 0x5712

        /** read 的读取窗口：正常首帧在百毫秒内到，2s 未见事件即答复 no_event。 */
        const val READ_TIMEOUT_MS = 2000L

        /** 秤同步窗口：扫描 + 连接 + 等一次测量通知共 10 秒（稿 ③ 文案与此一致）。 */
        const val SCALE_TIMEOUT_MS = 10000L

        /** Bluetooth SIG 标准体重秤服务 / 体重测量特征 / CCCD。 */
        val UUID_WEIGHT_SCALE_SERVICE: java.util.UUID =
            java.util.UUID.fromString("0000181d-0000-1000-8000-00805f9b34fb")
        val UUID_WEIGHT_MEASUREMENT: java.util.UUID =
            java.util.UUID.fromString("00002a9d-0000-1000-8000-00805f9b34fb")
        val UUID_CLIENT_CHARACTERISTIC_CONFIG: java.util.UUID =
            java.util.UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
