# SQLCipher：JNI 绑定依赖类名与 native 方法声明。
-keep class net.zetetic.** { *; }
-keep class net.sqlcipher.** { *; }

# package:jni（file_picker 传递依赖）：Dart 回调通过 JNI 按名注册。
-keep class com.github.dart_lang.jni.** { *; }

# flutter_secure_storage Android 端。
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# ONNX Runtime（flutter_onnxruntime）：JNI 在 convertToTensorInfo 里按 Java 类
# 反查 tensor 类型；R8 混淆后 `java_class == null` ⇒ **原生 SIGABRT**
# （2026-10-18 模拟器实测：Fatal signal 6，栈顶 OrtSession.run）。
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-keep class com.masicai.flutteronnxruntime.** { *; }
