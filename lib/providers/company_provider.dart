import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/company.dart';
import '../services/company_service.dart';

class CompanyProvider extends ChangeNotifier {
  CompanyProvider({FirebaseContext? context}) {
    debugPrint('[CompanyProvider] constructor called');
    setContext(context ?? FirebaseContextProvider.current, isInitial: true);
    FirebaseContextProvider.instance?.addListener(_onActiveContextChanged);
  }

  late FirebaseContext _context;
  late CompanyService _companyService;

  Company? _company;
  bool _isLoading = false;
  String? _currentCompanyId;
  StreamSubscription<Company?>? _companySub;
  StreamSubscription<User?>? _authSub;

  Company? get company => _company;
  bool get isLoading => _isLoading;
  String? get companyId => _currentCompanyId;
  bool get hasCompany => _company != null;

  /// Follows the app-wide active Firebase context (Master ↔ tenant swaps that
  /// happen during login/sign-out) so this provider always targets the project
  /// the current session belongs to.
  void _onActiveContextChanged() {
    final current = FirebaseContextProvider.current;
    if (_context.app.name != current.app.name) {
      setContext(current);
    }
  }

  void setContext(FirebaseContext context, {bool isInitial = false}) {
    if (!isInitial && _context.app.name == context.app.name) return;
    _context = context;
    _companyService = CompanyService(context: context);
    _authSub?.cancel();
    _authSub = _context.auth.idTokenChanges().listen((user) {
      debugPrint('[CompanyProvider] idTokenChanges: user=${user?.email}');
      if (user != null && _currentCompanyId == null) {
        resolveCompany(user.uid);
      } else if (user == null) {
        clear();
      }
    });
    if (!isInitial) {
      clear();
    }
  }

  Future<void> resolveCompany(String userId) async {
    debugPrint('[CompanyProvider.resolveCompany] userId=$userId');
    _isLoading = true;
    notifyListeners();

    try {
      final userDoc =
          await _context.firestore.collection('users').doc(userId).get();
      final companyId = userDoc.data()?['companyId'] as String?;
      debugPrint('[CompanyProvider.resolveCompany] companyId=$companyId');

      if (companyId != null && companyId.isNotEmpty) {
        _currentCompanyId = companyId;
        unawaited(_companyService.touchLastActive(companyId));
        _companySub?.cancel();
        _companySub =
            _companyService.streamCompany(companyId).listen((company) {
          debugPrint(
              '[CompanyProvider] company stream update: ${company?.name}');
          _company = company;
          _isLoading = false;
          notifyListeners();
        }, onError: (Object error, StackTrace s) {
          debugPrint('[CompanyProvider] company stream error: $error');
          _company = null;
          _isLoading = false;
          notifyListeners();
        });
      } else {
        debugPrint('[CompanyProvider.resolveCompany] no companyId found');
        _company = null;
        _currentCompanyId = null;
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[CompanyProvider.resolveCompany] error: $e');
      _company = null;
      _currentCompanyId = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> assignUserToCompany({
    required String userId,
    required String companyId,
  }) async {
    await _context.firestore.collection('users').doc(userId).set({
      'companyId': companyId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await resolveCompany(userId);
  }

  void clear() {
    debugPrint('[CompanyProvider.clear] called');
    _companySub?.cancel();
    _company = null;
    _currentCompanyId = null;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    debugPrint('[CompanyProvider.dispose] called');
    FirebaseContextProvider.instance?.removeListener(_onActiveContextChanged);
    _companySub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
