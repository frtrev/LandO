package com.neotheone.lando

import android.content.pm.PackageManager
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.maps.model.LatLng
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.model.CircularBounds
import com.google.android.libraries.places.api.net.SearchByTextRequest
import com.google.android.libraries.places.api.net.FindAutocompletePredictionsRequest
import com.google.android.libraries.places.api.net.FetchPlaceRequest
import com.google.android.libraries.places.api.model.AutocompleteSessionToken
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var placeSession: AutocompleteSessionToken? = null
    private var suggestionIDs: Set<String> = emptySet()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lando/places")
            .setMethodCallHandler { call, result ->
                if (call.method != "search" && call.method != "resolve") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                val key = info.metaData?.getString("com.google.android.geo.API_KEY")
                if (key.isNullOrBlank() || key.startsWith("YOUR_")) {
                    result.error("places_not_configured", "Google Places key is missing.", null)
                    return@setMethodCallHandler
                }
                if (!Places.isInitialized()) Places.initializeWithNewPlacesApiEnabled(applicationContext, key)
                val client = Places.createClient(this)
                if (call.method == "resolve") {
                    val id = call.argument<String>("placeId")
                    val token = placeSession
                    if (id == null || id !in suggestionIDs || token == null) {
                        result.error("places_selection_expired", "Search again to select this result.", null)
                        return@setMethodCallHandler
                    }
                    placeSession = null
                    suggestionIDs = emptySet()
                    val request = FetchPlaceRequest.builder(id, listOf(Place.Field.FORMATTED_ADDRESS, Place.Field.LOCATION)).setSessionToken(token).build()
                    client.fetchPlace(request).addOnSuccessListener { response ->
                        val place = response.place
                        val location = place.location
                        if (location == null) result.error("places_error", "No location returned.", null)
                        else result.success(mapOf("name" to (place.formattedAddress ?: call.argument<String>("name") ?: "Place"), "latitude" to location.latitude, "longitude" to location.longitude, "placeId" to id))
                    }.addOnFailureListener { placesError(it, result) }
                    return@setMethodCallHandler
                }
                val query = call.argument<String>("query")?.trim().orEmpty()
                if (query.isEmpty() || query.length > 300) {
                    result.error("invalid_query", "Enter an address or place (up to 300 characters).", null)
                    return@setMethodCallHandler
                }
                placeSession = null
                suggestionIDs = emptySet()
                val token = AutocompleteSessionToken.newInstance()
                val builder = FindAutocompletePredictionsRequest.builder().setQuery(query).setSessionToken(token)
                val lat = call.argument<Double>("latitude")
                val lon = call.argument<Double>("longitude")
                if (!query.contains(",") && lat != null && lon != null) builder.setLocationBias(CircularBounds.newInstance(LatLng(lat, lon), 50000.0))
                client.findAutocompletePredictions(builder.build()).addOnSuccessListener { response ->
                    val predictions = response.autocompletePredictions.take(5)
                    if (predictions.isEmpty()) {
                        searchText(query, lat, lon, result)
                    } else {
                        placeSession = token
                        suggestionIDs = predictions.map { it.placeId }.toSet()
                        result.success(predictions.map { mapOf("name" to it.getFullText(null).toString(), "placeId" to it.placeId) })
                    }
                }.addOnFailureListener { placesError(it, result) }
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

    private fun placesError(error: Exception, result: MethodChannel.Result) {
        result.error("places_error", "Google Places search failed.", mapOf("statusCode" to (error as? ApiException)?.statusCode))
    }

    private fun searchText(query: String, lat: Double?, lon: Double?, result: MethodChannel.Result) {
        val fields = listOf(Place.Field.DISPLAY_NAME, Place.Field.FORMATTED_ADDRESS, Place.Field.LOCATION)
        val builder = SearchByTextRequest.builder(query, fields).setMaxResultCount(5)
        if (!query.contains(",") && lat != null && lon != null) builder.setLocationBias(CircularBounds.newInstance(LatLng(lat, lon), 50000.0))
        Places.createClient(this).searchByText(builder.build()).addOnSuccessListener { response ->
            result.success(response.places.mapNotNull { place -> place.location?.let { location ->
                mapOf("name" to (place.formattedAddress ?: place.displayName ?: "Place"), "latitude" to location.latitude, "longitude" to location.longitude)
            } })
        }.addOnFailureListener { placesError(it, result) }
    }

}
