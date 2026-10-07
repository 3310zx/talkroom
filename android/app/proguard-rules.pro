# talkroom(llm_chat_app) v1.2.6 R8 keep 规则
# 原则：Flutter Dart 代码已 AOT 编译，R8 只作用于 Java/Kotlin 插件层；
# 保守 keep 引擎与反射/通道密集型插件，避免运行时 ClassNotFound / 反射失效。

# ---- Flutter 引擎 Java 层 ----
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# ---- flutter_secure_storage（反射 + 平台通道密集）----
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# ---- mobile_scanner（ML Kit 绑定）----
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn dev.steenbakker.mobile_scanner.**

# ---- syncfusion_flutter_pdf（纯 Dart 实现，keep 以防反射/注解处理）----
-keep class com.syncfusion.** { *; }
-dontwarn com.syncfusion.**

# ---- dynamic_color / flutter_math_fork：纯 Dart，无 Java 侧代码，无需 keep ----

# ---- 通用注解属性（插件可能使用注解反射）----
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
