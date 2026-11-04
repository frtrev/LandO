package com.neotheone.lando

import android.content.pm.PackageManager
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.maps.model.LatLng
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.model.CircularBounds
import com.google.android.libraries.places.api.net.SearchByTextRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lando/places")
            .setMethodCallHandler { call, result ->
                if (call.method != "search") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val query = call.argument<String>("query")?.trim().orEmpty()
                if (query.isEmpty() || query.length > 300) {
                    result.error("invalid_query", "Enter an address or place (up to 300 characters).", null)
                    return@setMethodCallHandler
                }
                val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                val key = info.metaData?.getString("com.google.android.geo.API_KEY")
                if (key.isNullOrBlank() || key.startsWith("YOUR_")) {
                    result.error("places_not_configured", "Google Places key is missing.", null)
                    return@setMethodCallHandler
                }
                if (!Places.isInitialized()) Places.initializeWithNewPlacesApiEnabled(applicationContext, key)
                val fields = listOf(Place.Field.DISPLAY_NAME, Place.Field.FORMATTED_ADDRESS, Place.Field.LOCATION)
                val builder = SearchByTextRequest.builder(query, fields).setMaxResultCount(5)
                val lat = call.argument<Double>("latitude")
                val lon = call.argument<Double>("longitude")
                if (lat != null && lon != null) builder.setLocationBias(CircularBounds.newInstance(LatLng(lat, lon), 50000.0))
                Places.createClient(this).searchByText(builder.build())
                    .addOnSuccessListener { response ->
                        result.success(response.places.mapNotNull { place ->
                            place.location?.let { location ->
                                mapOf("name" to (place.formattedAddress ?: place.displayName ?: "Place"), "latitude" to location.latitude, "longitude" to location.longitude)
                            }
                        })
                    }
                    .addOnFailureListener { error ->
                        // Return a numeric status only; SDK messages may contain credentials.
                        result.error("places_error", "Google Places search failed.", mapOf("statusCode" to (error as? ApiException)?.statusCode))
                    }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lando/config")
            .setMethodCallHandler { call, result ->
                if (call.method == "mapsConfigured") {
                    val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                    val key = info.metaData?.getString("com.google.android.geo.API_KEY")
                    result.success(!key.isNullOrBlank() && !key.startsWith("YOUR_"))
                } else result.notImplemented()
            }
    }
}
