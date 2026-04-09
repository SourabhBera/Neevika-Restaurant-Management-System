

package com.tobasu.Neevika 

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.util.Base64
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity: FlutterActivity() {
  private val CHANNEL = "usb_printer_channel"
  private val ACTION_USB_PERMISSION = "com.example.yourapp.USB_PERMISSION"

  private var usbManager: UsbManager? = null
  private var permissionReceiverRegistered = false
  private var pendingDeviceToOpen: UsbDevice? = null

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    usbManager = getSystemService(Context.USB_SERVICE) as UsbManager

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "printBytes" -> {
          val args = call.arguments as? Map<*, *>
          if (args == null) {
            result.error("INVALID_ARGS", "Arguments must be a map", null)
            return@setMethodCallHandler
          }
          val vendorId = (args["vendorId"] as? Number)?.toInt()
          val productId = (args["productId"] as? Number)?.toInt()
          val base64 = args["base64"] as? String
          val timeout = (args["timeout"] as? Number)?.toInt() ?: 2000

          if (vendorId == null || productId == null || base64 == null) {
            result.error("INVALID_ARGS", "vendorId/productId/base64 required", null)
            return@setMethodCallHandler
          }

          val bytes = Base64.decode(base64, Base64.DEFAULT)

          // run on background thread
          thread {
            try {
              val sent = openAndSendToUsbDevice(vendorId, productId, bytes, timeout)
              if (sent) {
                runOnUiThread { result.success("OK") }
              } else {
                runOnUiThread { result.error("SEND_FAILED", "Could not send or no matching device", null) }
              }
            } catch (e: Exception) {
              runOnUiThread { result.error("EXCEPTION", e.message, e.stackTraceToString()) }
            }
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun openAndSendToUsbDevice(vendorId: Int, productId: Int, data: ByteArray, timeout: Int): Boolean {
    val manager = usbManager ?: return false

    // Find device by VID/PID
    val device: UsbDevice? = manager.deviceList.values.firstOrNull { d ->
      d.vendorId == vendorId && d.productId == productId
    }

    val usbDevice = device ?: manager.deviceList.values.firstOrNull { d ->
      val name = d.deviceName ?: ""
      name.contains("printer", ignoreCase = true) || name.contains("pos", ignoreCase = true)
    } ?: return false

    // Request permission if needed
    if (!manager.hasPermission(usbDevice)) {
      val intent = Intent(ACTION_USB_PERMISSION)
      val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
      val pi = PendingIntent.getBroadcast(this, 0, intent, flag)
      val filter = IntentFilter(ACTION_USB_PERMISSION)
      registerReceiver(usbReceiver, filter)
      permissionReceiverRegistered = true
      pendingDeviceToOpen = usbDevice
      manager.requestPermission(usbDevice, pi)

      // wait briefly for permission
      var waited = 0
      while (!manager.hasPermission(usbDevice) && waited < 5000) {
        Thread.sleep(100)
        waited += 100
      }
      if (!manager.hasPermission(usbDevice)) {
        unregisterPermissionReceiver()
        return false
      }
    }

    val intf: UsbInterface? = (0 until usbDevice.interfaceCount).map { i -> usbDevice.getInterface(i) }
      .firstOrNull { iface ->
        (0 until iface.endpointCount).any { epIdx ->
          val ep = iface.getEndpoint(epIdx)
          ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT
        }
      }

    val iface = intf ?: usbDevice.getInterface(0)
    val connection: UsbDeviceConnection? = manager.openDevice(usbDevice)
    if (connection == null) {
      unregisterPermissionReceiver()
      return false
    }

    val claimed = connection.claimInterface(iface, true)
    if (!claimed) {
      connection.close()
      unregisterPermissionReceiver()
      return false
    }

    val endpoint: UsbEndpoint? = (0 until iface.endpointCount).map { i -> iface.getEndpoint(i) }
      .firstOrNull { ep -> ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT }

    if (endpoint == null) {
      connection.releaseInterface(iface)
      connection.close()
      unregisterPermissionReceiver()
      return false
    }

    val maxPacket = endpoint.maxPacketSize
    var offset = 0
    while (offset < data.size) {
      val chunkSize = minOf(maxPacket, data.size - offset)
      val chunk = data.copyOfRange(offset, offset + chunkSize)
      var sent = connection.bulkTransfer(endpoint, chunk, chunk.size, timeout)
      if (sent < 0) {
        var ok = false
        for (i in 0 until 3) {
          val s2 = connection.bulkTransfer(endpoint, chunk, chunk.size, timeout)
          if (s2 >= 0) { ok = true; break }
          Thread.sleep(50)
        }
        if (!ok) {
          connection.releaseInterface(iface)
          connection.close()
          unregisterPermissionReceiver()
          return false
        }
      }
      offset += chunkSize
      Thread.sleep(25) // pacing
    }

    Thread.sleep(200)
    connection.releaseInterface(iface)
    connection.close()
    unregisterPermissionReceiver()
    return true
  }

  private val usbReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
      if (intent == null) return
      if (intent.action == ACTION_USB_PERMISSION) {
        val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
        // we don't need to do more here; calling thread polls permission
        unregisterPermissionReceiver()
      }
    }
  }

  private fun unregisterPermissionReceiver() {
    if (permissionReceiverRegistered) {
      try {
        unregisterReceiver(usbReceiver)
      } catch (e: Exception) {
      }
      permissionReceiverRegistered = false
      pendingDeviceToOpen = null
    }
  }

  override fun onDestroy() {
    super.onDestroy()
    unregisterPermissionReceiver()
  }
}
