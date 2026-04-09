// services/print_service.dart

// Works across all platforms
export 'print_service_fallback.dart'
    if (dart.library.html) 'print_service_web.dart';
