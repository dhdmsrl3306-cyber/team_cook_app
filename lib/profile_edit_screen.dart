import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; 

class ProfileEditScreen extends StatefulWidget {
  final String loginId; 
  final Function(String) onNicknameChanged; 

  const ProfileEditScreen({
    super.key, 
    required this.loginId,
    required this.onNicknameChanged, 
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _currentPwErrorMessage;

  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsCodeController = TextEditingController(); 
  final TextEditingController _currentPwController = TextEditingController();
  final TextEditingController _newPwController = TextEditingController();
  bool _isSendingSms = false;
  bool _isLoading = true; 
  bool _isSaving = false; 
  String _errorMessage = ""; 
  String _documentId = ""; 
  String _dbPassword = ""; 
  String _originalPhoneNumber = "";

  // [기능 추가: 중복확인 상태 및 원본 값 변수]
  bool _isNicknameChecked = true;
  bool _isEmailChecked = true;
  String _originalNickname = "";
  String _originalEmail = "";

  // 🆕 실시간 하단 고정 메시지를 위한 상태 변수 추가
  String? _nicknameMessage;
  Color _nicknameMessageColor = Colors.green;
  String? _emailMessage;
  Color _emailMessageColor = Colors.green;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  String _verificationId = '';
  bool _isPhoneVerified = false; // 인증 완료 여부
  bool _isSmsSent = false;      // 문자 발송 여부
  String _phoneMessage = '';
  Color _phoneMsgColor = Colors.red;

  @override
  void initState() {
    super.initState();
    _fetchUserData(); 
  }

  // [기능 추가: 중복확인 로직 - 스낵바 대신 하단 문구 업데이트로 변경]
  Future<void> _checkNicknameDuplicate() async {
    final val = _nicknameController.text.trim();
    if (val == _originalNickname) {
      setState(() {
        _isNicknameChecked = true;
        _nicknameMessage = '현재 닉네임입니다.';
        _nicknameMessageColor = Colors.green;
      });
      return;
    }
    final snapshot = await FirebaseFirestore.instance.collection('users').where('nickname', isEqualTo: val).get();
    bool exists = snapshot.docs.any((doc) => doc.id != _documentId);
    setState(() {
      _isNicknameChecked = !exists;
      _nicknameMessage = exists ? '이미 사용 중인 닉네임입니다.' : '사용 가능한 닉네임입니다.';
      _nicknameMessageColor = exists ? Colors.red : Colors.green;
    });
  }

  Future<void> _checkEmailDuplicate() async {
    final val = _emailController.text.trim();
    if (val == _originalEmail) {
      setState(() {
        _isEmailChecked = true;
        _emailMessage = '현재 이메일입니다.';
        _emailMessageColor = Colors.green;
      });
      return;
    }
    final snapshot = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: val).get();
    bool exists = snapshot.docs.any((doc) => doc.id != _documentId);
    setState(() {
      _isEmailChecked = !exists;
      _emailMessage = exists ? '이미 사용 중인 이메일입니다.' : '사용 가능한 이메일입니다.';
      _emailMessageColor = exists ? Colors.red : Colors.green;
    });
  }

  Future<void> _fetchUserData() async {
    if (widget.loginId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = "전달받은 로그인 아이디가 비어있습니다. 다시 로그인해주세요.";
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('login_id', isEqualTo: widget.loginId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Firestore에서 해당 아이디('${widget.loginId}')의 회원 정보를 찾을 수 없습니다.";
        });
        return;
      }

      final doc = snapshot.docs.first;
      _documentId = doc.id; 
      
      final data = doc.data();
      _dbPassword = data['password'] ?? '';
      _originalPhoneNumber = data['phone_number'] ?? ''; 
      _originalNickname = data['nickname'] ?? ''; // 원본 저장
      _originalEmail = data['email'] ?? '';       // 원본 저장

      setState(() {
        _nicknameController.text = _originalNickname;
        _emailController.text = _originalEmail;
        _phoneController.text = _originalPhoneNumber;
        _isPhoneVerified = true; 
        _isLoading = false; 
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "데이터를 불러오는 중 에러가 발생했습니다:\n$e";
      });
    }
  }

  Future<void> _sendVerificationCode() async {
    final rawPhoneNumber = _phoneController.text.trim();
    if (rawPhoneNumber.isEmpty) {
      _showSnackBar('휴대폰 번호를 입력해주세요.', Colors.red);
      return;
    }

    setState(() => _isSendingSms = true);

    String formattedPhone = rawPhoneNumber;
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '+82${formattedPhone.substring(1)}';
    } else if (!formattedPhone.startsWith('+')) {
      formattedPhone = '+82$formattedPhone';
    }

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _isSmsSent = true;
            _isSendingSms = false;
          });
          _showSnackBar('인증번호 문자가 발송되었습니다! 💬', Colors.blue);
        },
        verificationCompleted: (PhoneAuthCredential credential) async {
          setState(() {
            _isPhoneVerified = true;
            _isSmsSent = false;
            _isSendingSms = false;
          });
          _showSnackBar('휴대폰 번호가 자동으로 인증되었습니다! 🎉', Colors.green);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isSendingSms = false);
          _showSnackBar('SMS 발송 실패: ${e.message}', Colors.red);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _isSendingSms = false);
      _showSnackBar('인증 시스템 오류: $e', Colors.red);
    }
  }

  Future<void> _verifySmsCode() async {
    final smsCode = _smsCodeController.text.trim();
    if (smsCode.isEmpty || smsCode.length < 6) {
      _showSnackBar('6자리 인증번호를 정확히 입력해주세요.', Colors.red);
      return;
    }

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: smsCode,
      );

      await _auth.signInWithCredential(credential);

      setState(() {
        _isPhoneVerified = true;
        _isSmsSent = false;
      });
      _showSnackBar('휴대폰 인증이 완료되었습니다! ✅', Colors.green);
    } catch (e) {
      _showSnackBar('인증번호가 일치하지 않거나 만료되었습니다.', Colors.red);
    }
  }

 Future<void> _updateUserData() async {
  // 1. 기존 유효성 검사들 (닉네임, 이메일, 휴대폰)
  if (!_isNicknameChecked) {
    _showSnackBar('닉네임 중복확인을 완료해주세요.', Colors.red);
    return;
  }
  if (!_isEmailChecked) {
    _showSnackBar('이메일 중복확인을 완료해주세요.', Colors.red);
    return;
  }
  String newPhoneNumber = _phoneController.text.trim();
    bool isPhoneNumberChanged = (newPhoneNumber != _originalPhoneNumber);
  if (isPhoneNumberChanged && !_isPhoneVerified) {
      _showSnackBar('변경된 휴대폰 번호 인증을 완료해주세요.', Colors.red);
      return;
    }

  // 2. 비밀번호 변경 시도 로직 (실시간 검증 메시지 적용)
  final currentPwInput = _currentPwController.text;
  final newPwInput = _newPwController.text;

  // 비밀번호 변경을 시도하려는 경우(비밀번호 칸 중 하나라도 입력된 경우)
  if (currentPwInput.isNotEmpty || newPwInput.isNotEmpty) {
    // [핵심 추가] 현재 비밀번호 틀리면 실시간 메시지 발생
    if (currentPwInput != _dbPassword) {
      setState(() {
        _currentPwErrorMessage = '기존 비밀번호가 일치하지 않습니다.';
      });
      return;
    }
    
    // 새 비밀번호가 입력되지 않았을 경우
    if (newPwInput.isEmpty) {
      _showSnackBar('새로운 비밀번호를 입력해주세요.', Colors.red);
      return;
    }
  }

  if (!_formKey.currentState!.validate()) return;

  setState(() => _isSaving = true);

  Map<String, dynamic> updateData = {
    'nickname': _nicknameController.text.trim(),
    'email': _emailController.text.trim(),
    'phone': _phoneController.text.trim(),
  };

  // 비밀번호 변경 시에만 데이터 추가
  if (newPwInput.isNotEmpty) {
    updateData['password'] = newPwInput;
  }

  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_documentId)
        .update(updateData);

    widget.onNicknameChanged(_nicknameController.text.trim());
    _showSnackBar('프로필이 성공적으로 수정되었습니다!', Colors.green);
    if (!mounted) return;
    Navigator.pop(context);
  } catch (e) {
    _showSnackBar('수정 실패: $e', Colors.red);
  } finally {
    setState(() => _isSaving = false);
  }
}
Future<void> _deleteAccount() async {
  final confirmPw = await _showPasswordDialog();
  if (confirmPw == null || confirmPw != _dbPassword) {
    _showSnackBar('비밀번호가 일치하지 않아 탈퇴할 수 없습니다.', Colors.red);
    return;
  }

  bool confirm = await _showConfirmDialog();
  if (!confirm) return;

  setState(() => _isSaving = true);
  try {
    await FirebaseFirestore.instance.collection('users').doc(_documentId).delete();
    await FirebaseAuth.instance.currentUser?.delete();
    _showSnackBar('탈퇴가 완료되었습니다.', Colors.green);
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  } catch (e) {
    _showSnackBar('탈퇴 처리 중 오류 발생: $e', Colors.red);
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}

Future<String?> _showPasswordDialog() async {
  TextEditingController pwController = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('비밀번호 확인'),
      content: TextField(controller: pwController, obscureText: true, decoration: const InputDecoration(hintText: '기존 비밀번호 입력')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, pwController.text), child: const Text('확인')),
      ],
    ),
  );
}

Future<bool> _showConfirmDialog() async {
  return await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('정말 탈퇴하시겠습니까?'),
      content: const Text('모든 데이터가 삭제되며 복구할 수 없습니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('탈퇴')),
      ],
    ),
  ) ?? false;
}

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('회원 정보 수정', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 55,
                                backgroundColor: Colors.grey.shade200,
                                child: Icon(Icons.person, size: 65, color: Colors.grey.shade400),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.deepOrange,
                                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),

                        // [기능 추가: 닉네임 UI 및 중복확인 버튼]
                        const Text('닉네임 변경', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _nicknameController,
                                onChanged: (v) => setState(() {
                                  _nicknameMessage = null; // 입력 변경 시 하단 고정 문구 클리어
                                  _isNicknameChecked = (v == _originalNickname);
                                }),
                                decoration: InputDecoration(
                                  hintText: '새로운 닉네임을 입력하세요',
                                  prefixIcon: const Icon(Icons.badge_outlined),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(onPressed: _checkNicknameDuplicate, 
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                            child: const Text('중복확인',style: TextStyle(color: Colors.white))),
                          ],
                        ),
                        // 🆕 기존 디자인 유지한 상태에서 하단 고정 메시지만 추가
                        if (_nicknameMessage != null) ...[
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              _nicknameMessage!,
                              style: TextStyle(fontSize: 13, color: _nicknameMessageColor, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // [기능 추가: 이메일 UI 및 중복확인 버튼]
                        const Text('이메일 주소', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _emailController,
                                onChanged: (v) => setState(() {
                                  _emailMessage = null; // 입력 변경 시 하단 고정 문구 클리어
                                  _isEmailChecked = (v == _originalEmail);
                                }),
                                decoration: InputDecoration(
                                  hintText: '이메일을 입력하세요',
                                  prefixIcon: const Icon(Icons.email_outlined),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(onPressed: _checkEmailDuplicate, 
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                            child: const Text('중복확인',style: TextStyle(color: Colors.white))),
                          ],
                        ),
                        // 🆕 기존 디자인 유지한 상태에서 하단 고정 메시지만 추가
                        if (_emailMessage != null) ...[
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              _emailMessage!,
                              style: TextStyle(fontSize: 13, color: _emailMessageColor, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),

                        const Text('휴대폰 번호', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                enabled: !_isPhoneVerified || _phoneController.text.trim() == _originalPhoneNumber, 
                                decoration: InputDecoration(
                                  hintText: '하이픈(-) 없이 숫자만 입력',
                                  prefixIcon: const Icon(Icons.phone_android_outlined),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onChanged: (val) {
                                  if (val.trim() != _originalPhoneNumber) {
                                    if (_isPhoneVerified) {
                                      setState(() { _isPhoneVerified = false; });
                                    }
                                  } else {
                                    if (!_isPhoneVerified) {
                                      setState(() { _isPhoneVerified = true; _isSmsSent = false; });
                                    }
                                  }
                                },
                              ),
                            ),
                            if (_phoneController.text.trim() != _originalPhoneNumber) ...[
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 55,
                                child: ElevatedButton(
                                  onPressed: (_isPhoneVerified || _isSendingSms) ? null : _sendVerificationCode,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isPhoneVerified ? Colors.green : Colors.deepOrange,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: _isSendingSms
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : Text(_isPhoneVerified ? '인증 완료' : (_isSmsSent ? '재전송' : '인증 요청'), style: const TextStyle(color: Colors.white)),
                                ),
                              ),
                            ],
                          ],
                        ),

                        if (_isSmsSent && !_isPhoneVerified) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _smsCodeController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: '6자리 인증번호 입력',
                                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 55,
                                child: ElevatedButton(
                                  onPressed: _verifySmsCode,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepOrange,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('번호 확인', style: TextStyle(color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 25),
                        const Divider(thickness: 1, color: Color(0xFFEEEEEE)),
                        const SizedBox(height: 15),

                        const Text('비밀번호 변경', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        // [비밀번호 변경 섹션의 TextFormField 부분을 아래와 같이 수정]
                        TextFormField(
                          controller: _currentPwController,
                          obscureText: true,
                          onChanged: (v) {
                            if (_currentPwErrorMessage != null) {
                              setState(() => _currentPwErrorMessage = null); // 다시 입력하면 메시지 숨김
                            }
                          },
                          decoration: InputDecoration(
                            hintText: '기존 비밀번호 입력',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        // 🆕 메시지 출력 부분 추가
                        if (_currentPwErrorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 5),
                            child: Text(
                              _currentPwErrorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _newPwController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: '새로운 비밀번호 (6자리 이상)',
                            prefixIcon: const Icon(Icons.lock_reset_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 40),

                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _updateUserData,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isSaving
                                ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white))
                                : const Text('변경사항 저장하기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: TextButton(
                            onPressed: _deleteAccount,
                            child: const Text('회원 탈퇴하기', style: TextStyle(color: Colors.red, fontSize : 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose(); 
    _currentPwController.dispose();
    _newPwController.dispose();
    super.dispose();
  }
}