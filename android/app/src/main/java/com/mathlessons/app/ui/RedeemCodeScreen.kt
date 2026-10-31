package com.mathlessons.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mathlessons.app.data.LessonsRepository
import kotlinx.coroutines.launch

@Composable
fun RedeemCodeScreen(repository: LessonsRepository, onDone: () -> Unit) {
    var code by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
        Text("تفعيل كود", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(16.dp))

        OutlinedTextField(
            value = code,
            onValueChange = { code = it.uppercase() },
            label = { Text("الكود") },
            placeholder = { Text("XXXXX-XXXXX") },
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(Modifier.height(12.dp))

        Button(
            onClick = {
                loading = true
                status = null
                scope.launch {
                    val result = repository.redeemCode(code.trim())
                    loading = false
                    if (result.status == "redeemed") {
                        status = "تم تفعيل الدرس بنجاح ✅"
                        onDone()
                    } else {
                        status = result.error ?: "تعذر تفعيل الكود"
                    }
                }
            },
            enabled = code.isNotBlank() && !loading,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (loading) "جاري التحقق..." else "تفعيل")
        }

        status?.let {
            Spacer(Modifier.height(12.dp))
            Text(it)
        }
    }
}
