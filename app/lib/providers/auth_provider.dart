import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/data/local_cache_service.dart';
import 'package:sanitary_pricing_app/data/supabase_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthState {
  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.isDemoMode = true,
    this.userId,
    this.fullName = 'مدير المحل',
    this.role = 'admin',
    this.isActive = true,
    this.errorMessage,
  });

  final bool isLoading;
  final bool isAuthenticated;
  final bool isDemoMode;
  final String? userId;
  final String fullName;
  final String role;
  final bool isActive;
  final String? errorMessage;

  bool get isAdmin => role == 'admin' && isActive;

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    bool? isDemoMode,
    String? userId,
    String? fullName,
    String? role,
    bool? isActive,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isDemoMode: isDemoMode ?? this.isDemoMode,
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription<dynamic>? _authSub;

  @override
  AuthState build() {
    if (AppConfig.isDemoMode) {
      return const AuthState(
        isAuthenticated: true,
        isDemoMode: true,
        fullName: 'عمر (وضع التجربة)',
        role: 'admin',
      );
    }

    final client = Supabase.instance.client;
    _authSub?.cancel();
    _authSub = client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        unawaited(_loadProfile());
      } else {
        state = const AuthState(
          isAuthenticated: false,
          isDemoMode: false,
        );
      }
    });

    ref.onDispose(() {
      _authSub?.cancel();
    });

    final currentSession = client.auth.currentSession;
    if (currentSession != null) {
      Future.microtask(_loadProfile);
      return const AuthState(
        isLoading: true,
        isAuthenticated: true,
        isDemoMode: false,
      );
    }

    return const AuthState(
      isAuthenticated: false,
      isDemoMode: false,
    );
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await SupabaseRepository().fetchCurrentProfile();
      if (profile == null || !profile.isActive) {
        await Supabase.instance.client.auth.signOut();
        state = const AuthState(
          isAuthenticated: false,
          isDemoMode: false,
          errorMessage: 'هذا الحساب غير مفعّل. راجع مدير المحل.',
        );
        return;
      }

      state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        isDemoMode: false,
        userId: profile.id,
        fullName: profile.fullName,
        role: profile.role,
        isActive: profile.isActive,
      );
    } on AppException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'تعذر تحميل بيانات الحساب.',
      );
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    if (AppConfig.isDemoMode) return true;

    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      state = state.copyWith(errorMessage: 'يرجى إدخال بريد إلكتروني صحيح.');
      return false;
    }
    if (password.length < 8) {
      state = state.copyWith(
        errorMessage: 'كلمة المرور يجب أن تكون 8 أحرف على الأقل.',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );
      await _loadProfile();
      return state.isAuthenticated;
    } on AuthException {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'تعذر الاتصال بالسيرفر، تأكد من الإنترنت وحاول مجدداً.',
      );
      return false;
    }
  }

  Future<void> signOut() async {
    if (!AppConfig.isDemoMode) {
      await Supabase.instance.client.auth.signOut();
    }
    await LocalCacheService.clearSessionCache();
    state = AuthState(
      isAuthenticated: AppConfig.isDemoMode,
      isDemoMode: AppConfig.isDemoMode,
    );
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
