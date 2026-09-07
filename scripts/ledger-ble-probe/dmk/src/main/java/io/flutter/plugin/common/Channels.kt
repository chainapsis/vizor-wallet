package io.flutter.plugin.common

// Test-only method-channel endpoint interfaces. No Flutter engine or codec runs.
class MethodCall(val method: String, private val arguments: Map<String, Any?>?) {
    @Suppress("UNCHECKED_CAST")
    fun <T> argument(key: String): T? = arguments?.get(key) as T?
}
class MethodChannel {
    interface Result {
        fun success(result: Any?)
        fun error(errorCode: String, errorMessage: String?, errorDetails: Any?)
        fun notImplemented()
    }
}
class EventChannel {
    interface StreamHandler {
        fun onListen(arguments: Any?, events: EventSink)
        fun onCancel(arguments: Any?)
    }
    interface EventSink { fun success(event: Any?) }
}
