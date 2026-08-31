package com.lumovault.core.database.converters

import androidx.room.TypeConverter
import org.json.JSONArray

class EmbeddingConverter {

    @TypeConverter
    fun fromFloatList(value: List<Float>): String {
        val array = JSONArray()
        value.forEach { array.put(it.toDouble()) }
        return array.toString()
    }

    @TypeConverter
    fun toFloatList(value: String): List<Float> {
        return try {
            val array = JSONArray(value)
            (0 until array.length()).map { array.getDouble(it).toFloat() }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
