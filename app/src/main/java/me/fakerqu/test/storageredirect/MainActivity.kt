package me.fakerqu.test.storageredirect

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import me.fakerqu.test.storageredirect.ui.screen.MediaAccessViewModel
import me.fakerqu.test.storageredirect.ui.screen.MediaStoreScreen
import top.yukonga.miuix.kmp.theme.MiuixTheme

class MainActivity : ComponentActivity() {
    private val viewModel: MediaAccessViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startForegroundService(Intent(this, TestService::class.java))
        enableEdgeToEdge()
        setContent {
            MiuixTheme {
                MediaStoreScreen(viewModel)
            }
        }
    }
}