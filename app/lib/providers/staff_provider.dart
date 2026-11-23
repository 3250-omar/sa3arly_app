import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/data/supabase_repository.dart';
import 'package:sanitary_pricing_app/providers/auth_provider.dart';

class StaffNotifier extends Notifier<List<UserProfile>> {
  @override
  List<UserProfile> build() {
    final auth = ref.watch(authProvider);
    if (AppConfig.isDemoMode) {
      return const [
        UserProfile(
          id: 'staff-1',
          fullName: 'عمر (المالك)',
          role: 'admin',
          isActive: true,
        ),
        UserProfile(
          id: 'staff-2',
          fullName: 'محمد (بائع)',
          role: 'staff',
          isActive: true,
        ),
        UserProfile(
          id: 'staff-3',
          fullName: 'يوسف (بائع)',
          role: 'staff',
          isActive: true,
        ),
      ];
    }

    if (auth.isAuthenticated && auth.isAdmin) {
      Future.microtask(refresh);
    }
    return const [];
  }

  Future<void> refresh() async {
    if (AppConfig.isDemoMode) return;
    try {
      final list = await SupabaseRepository().fetchAllProfiles();
      state = list;
    } catch (_) {
      // Keep cached/previous list if offline
    }
  }

  bool _wouldLeaveZeroActiveAdmins(UserProfile target,
      {required String nextRole, required bool nextActive}) {
    final activeAdminsCount =
        state.where((p) => p.role == 'admin' && p.isActive).length;
    final wasActiveAdmin = target.role == 'admin' && target.isActive;
    final willBeActiveAdmin = nextRole == 'admin' && nextActive;
    return wasActiveAdmin && !willBeActiveAdmin && activeAdminsCount <= 1;
  }

  /// Returns an error message if prevented (e.g., last active admin), else null.
  String? toggleRole(String id) {
    final idx = state.indexWhere((p) => p.id == id);
    if (idx < 0) return null;
    final target = state[idx];
    final nextRole = target.role == 'admin' ? 'staff' : 'admin';

    if (_wouldLeaveZeroActiveAdmins(
      target,
      nextRole: nextRole,
      nextActive: target.isActive,
    )) {
      return 'لا يمكن تخفيض صلاحية آخر مدير نشط في المحل';
    }

    final updated = UserProfile(
      id: target.id,
      fullName: target.fullName,
      role: nextRole,
      isActive: target.isActive,
    );
    final copy = [...state];
    copy[idx] = updated;
    state = copy;

    if (!AppConfig.isDemoMode) {
      unawaited(
        SupabaseRepository()
            .updateProfile(
              id: updated.id,
              role: updated.role,
              isActive: updated.isActive,
            )
            .catchError((_) {}),
      );
    }
    return null;
  }

  /// Returns an error message if prevented (e.g., last active admin), else null.
  String? toggleActive(String id) {
    final idx = state.indexWhere((p) => p.id == id);
    if (idx < 0) return null;
    final target = state[idx];
    final nextActive = !target.isActive;

    if (_wouldLeaveZeroActiveAdmins(
      target,
      nextRole: target.role,
      nextActive: nextActive,
    )) {
      return 'لا يمكن تعطيل حساب آخر مدير نشط في المحل';
    }

    final updated = UserProfile(
      id: target.id,
      fullName: target.fullName,
      role: target.role,
      isActive: nextActive,
    );
    final copy = [...state];
    copy[idx] = updated;
    state = copy;

    if (!AppConfig.isDemoMode) {
      unawaited(
        SupabaseRepository()
            .updateProfile(
              id: updated.id,
              role: updated.role,
              isActive: updated.isActive,
            )
            .catchError((_) {}),
      );
    }
    return null;
  }
}

final staffProvider = NotifierProvider<StaffNotifier, List<UserProfile>>(
  StaffNotifier.new,
);
