# 2026-11-06 修复计划

## 批次 1（P0/P1 数据破坏）

1. F-01 槽位回调/串餐：先写跨槽位 widget 回归，改成按 slot 传递。
2. F-03 meal item scan metadata round-trip：先写 repository update/restore/partial delete 回归。
3. F-04/F-05 删除 FK 链：先写 venue old snapshot、recognition、cardio 的 delete/clear/restore 回归，按事务顺序修。
4. F-02 nested Navigator：先写真实 nested Navigator 宿主回归，修为只关闭当前 sheet。

## 批次 2（边界与可靠性）

5. F-06 old backup defaults + numeric validation。
6. F-07 repository date window + 全部日期边界。
7. F-08 menu publish atomic。
8. F-09 executor DB error isolation。
9. F-10 nutrition numeric boundary。

## 批次 3（用户可见/发布）

10. 手动编辑单位/失败反馈/撤销 mounted guard。
11. progress semantics 与极端字号补扫。
12. 文档与发布 metadata 对齐、version bump 2112、APK 级 release gate。

任何同一项连续两轮不绿则登记 BLOCKER，不扩大范围；P2 不伪装成已修。
