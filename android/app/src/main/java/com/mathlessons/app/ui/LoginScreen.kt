package com.mathlessons.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mathlessons.app.data.LessonsRepository
import kotlinx.coroutines.launch

@Composable
fun LoginScreen(repository: LessonsRepository, onLoggedIn: () -> Unit) {
    var email by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var codeSent by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("دروس الرياضيات", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(8.dp))
        Text(
            if (!codeSent) "سجّل دخول بنفس البريد المستخدم بالموقع"
            else "أدخل الكود المكوّن من 6 أرقام اللي وصلك بالبريد",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(24.dp))

        if (!codeSent) {
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("البريد الإلكتروني") },
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(Modifier.height(12.dp))

            Button(
                onClick = {
                    loading = true
                    status = null
                    scope.launch {
                        try {
                            repository.sendLoginCode(email.trim())
                            codeSent = true
                            status = null
                        } catch (e: Exception) {
                            status = "خطأ: ${e.message}"
                        } finally {
                            loading = false
                        }
                    }
                },
                enabled = email.isNotBlank() && !loading,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(if (loading) "جاري الإرسال..." else "إرسال كود الدخول")
            }
        } else {
            OutlinedTextField(
                value = code,
                onValueChange = { code = it },
                label = { Text("الكود (6 أرقام)") },
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(Modifier.height(12.dp))

            Button(
                onClick = {
                    loading = true
                    status = null
                    scope.launch {
                        try {
                            repository.verifyLoginCode(email.trim(), code.trim())
                            onLoggedIn()
                        } catch (e: Exception) {
                            status = "كود غير صحيح أو منتهي: ${e.message}"
                        } finally {
                            loading = false
                        }
                    }
                },
                enabled = code.isNotBlank() && !loading,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(if (loading) "جاري التحقق..." else "دخول")
            }

            Spacer(Modifier.height(8.dp))

            TextButton(onClick = { codeSent = false; code = "" }) {
                Text("تغيير البريد الإلكتروني")
            }
        }

        status?.let {
            Spacer(Modifier.height(12.dp))
            Text(it, style = MaterialTheme.typography.bodySmall)
        }
    }
}
