import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------
// users 문서 찾기 도우미
// ---------------------------------------------------------
// 앱의 loginId 는 상황에 따라 값이 다릅니다.
//  - 자동 로그인: Firebase Auth uid (= users 문서 ID)
//  - 직접 로그인: users 문서의 'login_id' 필드 값
// 회원가입 시 문서는 uid 로 만들어지기 때문에 doc(loginId) 만으로는
// 직접 로그인한 경우 실제 문서를 못 찾습니다. 두 경우 모두 처리합니다.
final Map<String, DocumentReference<Map<String, dynamic>>> _userDocRefCache = {};

Future<DocumentReference<Map<String, dynamic>>?> resolveUserDocRef(
  String loginId,
) async {
  if (loginId.isEmpty) return null;
  final cached = _userDocRefCache[loginId];
  if (cached != null) return cached;

  final users = FirebaseFirestore.instance.collection('users');
  DocumentReference<Map<String, dynamic>>? ref;

  // 1) login_id 필드로 먼저 찾고 (직접 로그인)
  final query =
      await users.where('login_id', isEqualTo: loginId).limit(1).get();
  if (query.docs.isNotEmpty) {
    ref = query.docs.first.reference;
  } else {
    // 2) 없으면 문서 ID(uid)로 찾습니다 (자동 로그인)
    final direct = await users.doc(loginId).get();
    if (direct.exists) ref = direct.reference;
  }

  if (ref != null) _userDocRefCache[loginId] = ref;
  return ref;
}

// ---------------------------------------------------------
// 프로필 사진 도우미
// ---------------------------------------------------------
// 프로필 사진은 레시피 사진과 같은 방식으로 "data:image/jpeg;base64,..." 문자열을
// users 문서의 'profile_image' 필드에 저장합니다. (Firebase Storage 미사용)
const String kProfileImageField = 'profile_image';

String bytesToDataUri(Uint8List bytes) =>
    'data:image/jpeg;base64,${base64Encode(bytes)}';

ImageProvider? profileImageProvider(String? dataUri) {
  if (dataUri == null || dataUri.isEmpty) return null;
  try {
    if (dataUri.startsWith('data:image')) {
      return MemoryImage(base64Decode(dataUri.substring(dataUri.indexOf(',') + 1)));
    }
    if (dataUri.startsWith('http')) return NetworkImage(dataUri);
  } catch (_) {}
  return null;
}

/// users 문서를 실시간으로 구독해서 프로필 사진(없으면 기본 아이콘)을 보여주는 아바타.
class UserProfileAvatar extends StatelessWidget {
  final String loginId;
  final double radius;
  final Color backgroundColor;
  final Color iconColor;

  const UserProfileAvatar({
    super.key,
    required this.loginId,
    this.radius = 35,
    this.backgroundColor = Colors.deepOrange,
    this.iconColor = Colors.white,
  });

  Widget _avatar(ImageProvider? image) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: image,
        child: image == null
            ? Icon(Icons.person, color: iconColor, size: radius * 1.15)
            : null,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentReference<Map<String, dynamic>>?>(
      future: resolveUserDocRef(loginId),
      builder: (context, refSnap) {
        final ref = refSnap.data;
        if (ref == null) return _avatar(null);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snap) {
            final raw = snap.data?.data()?[kProfileImageField]?.toString();
            return _avatar(profileImageProvider(raw));
          },
        );
      },
    );
  }
}
