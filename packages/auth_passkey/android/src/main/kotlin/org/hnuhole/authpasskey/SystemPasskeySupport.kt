package org.hnuhole.authpasskey

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import androidx.credentials.PublicKeyCredential

/** Local conservative preflight only. No account names or provider data leave the device. */
internal object SystemPasskeySupport {
    // AOSP system-provider discovery action. Querying a service declaration does
    // not bind to it or use the privileged provider enumeration APIs.
    private const val ACTION = "android.service.credentials.system.CredentialProviderService"
    private const val METADATA = "android.credentials.provider"

    data class Provider(val packageName: String, val system: Boolean, val protected: Boolean, val publicKey: Boolean)

    fun eligible(api: Int, feature: Boolean, secure: Boolean, providers: List<Provider>): Boolean {
        if (api < 34 || !feature || !secure || providers.isEmpty()) return false
        // Creation cannot allowlist individual components. If a Google system
        // candidate exists, fail closed instead of presenting it as an OEM flow.
        if (providers.any { it.packageName == "com.google" || it.packageName.startsWith("com.google.") }) return false
        return providers.all { it.system && it.protected } && providers.any { it.publicKey }
    }

    fun available(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 34) return false
        return try {
            val pm = context.packageManager
            val providers = pm.queryIntentServices(Intent(ACTION), PackageManager.GET_META_DATA).mapNotNull { resolved ->
                val service = resolved.serviceInfo ?: return@mapNotNull null
                if (!service.enabled || !service.applicationInfo.enabled) return@mapNotNull null
                val xml = service.loadXmlMetaData(pm, METADATA)
                var publicKey = false
                xml?.use {
                    while (it.eventType != org.xmlpull.v1.XmlPullParser.END_DOCUMENT) {
                        if (it.eventType == org.xmlpull.v1.XmlPullParser.START_TAG && it.name == "capability" &&
                            it.getAttributeValue(null, "name") == PublicKeyCredential.TYPE_PUBLIC_KEY_CREDENTIAL) publicKey = true
                        it.next()
                    }
                }
                Provider(service.packageName,
                    service.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0,
                    service.permission == "android.permission.BIND_CREDENTIAL_PROVIDER_SERVICE", publicKey)
            }
            eligible(Build.VERSION.SDK_INT, pm.hasSystemFeature(PackageManager.FEATURE_CREDENTIALS),
                context.getSystemService(KeyguardManager::class.java)?.isDeviceSecure == true, providers)
        } catch (_: Exception) { false }
    }
}
