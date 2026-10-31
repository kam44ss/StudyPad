package com.mathlessons.app.data

import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest

/**
 * إعدادات الاتصال بـ Supabase.
 * TODO: استبدل هذا بإعدادات مشروعك الفعلي (Project Settings > API بلوحة Supabase)
 */
object SupabaseClientProvider {

    private const val SUPABASE_URL = "https://yaedtkfcpygpbyzzkwya.supabase.co"
    private const val SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlhZWR0a2ZjcHlncGJ5enprd3lhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQzOTg1MjcsImV4cCI6MjA5OTk3NDUyN30.5ZYj9CwEaaUUF3QcV55fWnes7qVxlaGq3-UYq-f6wtI"

    val client = createSupabaseClient(
        supabaseUrl = SUPABASE_URL,
        supabaseKey = SUPABASE_ANON_KEY
    ) {
        install(Auth)
        install(Postgrest)
        install(Functions)
    }
}
