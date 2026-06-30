import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'profile_edit_screen.dart';

// ---------------------------------------------------------
// 전역 임시 데이터 (UI 및 하트 찜하기 연동용 스크랩 리스트)
// ---------------------------------------------------------
List<Map<String, dynamic>> globalScrapList = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const TeamCookApp());
}

class TeamCookApp extends StatelessWidget {
  const TeamCookApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Team Cook',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const SplashScreen(),
    );
  }
}

// ---------------------------------------------------------
// 1. 스플래시 & 루트 내비게이션
// ---------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const RootScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF8A00), Color(0xFFFF6200)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu, size: 80, color: Colors.white),
            SizedBox(height: 20),
            Text(
              'TEAM COOK',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _selectedIndex = 0;
  bool isLoggedIn = false;
  String userName = "";
  String loginId = "";
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userStatusSubscription;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> onLoginSuccess(String name, String id) async {
     var userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(id)
      .get();

    if (userDoc.exists && userDoc.data() != null) {

      final data = userDoc.data()!;

      if (data['user_status'] == 'suspended') {

        final until = data['suspendedUntil'];

        // 기간 정지
        if (until != null &&
            until.toDate().isAfter(DateTime.now())) {

          await FirebaseAuth.instance.signOut();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '정지된 계정입니다.\n'
                '사유: ${data['suspensionReason'] ?? '사유 없음'}'
              ),
            ),
          );

          return; // 로그인 중단
        }

        // 기간 만료 자동 해제
         if (until != null &&
          !until.toDate().isAfter(DateTime.now())) {

          await FirebaseFirestore.instance
              .collection('users')
              .doc(id)
              .update({
            'user_status': 'active',
            'suspensionReason': '',
            'suspendedUntil': null,
          });

        }
      }
    }
    setState(() {
      isLoggedIn = true;
      userName = name;
      loginId = id;
    });

    _listenToUserStatus(id);

    if (userDoc.exists && userDoc.data() != null) {
      final data = userDoc.data()!;
      setState(() {
        globalScrapList = List<Map<String, dynamic>>.from(data['scraps'] ?? []);
      });
    } else {
      setState(() {
        globalScrapList = [];
      });
    }
  }
 void _listenToUserStatus(String id) {
  _userStatusSubscription?.cancel();

  _userStatusSubscription = FirebaseFirestore.instance
      .collection('users')
      .doc(id)
      .snapshots()
      .listen((snapshot) async {

    if (snapshot.exists && snapshot.data() != null) {

      final Map<String, dynamic> data = snapshot.data()!;

      final String userStatus =
          data['user_status']?.toString() ?? 'active';

      final dynamic suspendedUntilData =
          data['suspendedUntil'];


      if (userStatus == 'suspended') {

        // 기간 정지
        if (suspendedUntilData != null) {

          final DateTime suspendedUntil =
              (suspendedUntilData is Timestamp)
                  ? suspendedUntilData.toDate()
                  : DateTime.parse(
                      suspendedUntilData.toString()
                    );


          // 아직 정지 중
          if (DateTime.now().isBefore(suspendedUntil)) {

            _forceLogout(
              suspendedUntil,
              data['suspensionReason']?.toString()
                  ?? '사유 미작성',
            );

          }

          // 기간 종료 → 자동 해제
          else {

            await FirebaseFirestore.instance
                .collection('users')
                .doc(id)
                .update({

              'user_status': 'active',
              'suspensionReason': '',
              'suspendedUntil': null,

            });

          }

        }

        // 영구 정지
        else {

          _forceLogout(
            DateTime.now(),
            data['suspensionReason']?.toString()
                ?? '사유 미작성',
          );

        }
      }
    }
  });
}
  void _forceLogout(
    DateTime suspendedUntil,
    String reason,
  ) {
    setState(() {
      isLoggedIn = false;
      userName = "";
      loginId = "";
      globalScrapList.clear();
    });

    FirebaseAuth.instance.signOut();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '이용이 제한되었습니다.\n'
          '해제 시간: $suspendedUntil\n'
          '사유: $reason',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _userStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkAutoLogin() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      String name = "사용자";
      if (userDoc.exists) {
        name = userDoc.data()?['nickname'] ?? "사용자";
      }
      await onLoginSuccess(name, user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeScreen(isLoggedIn: isLoggedIn, loginId: loginId, userName: userName),
      SearchScreen(isLoggedIn: isLoggedIn, loginId: loginId),
      ScrapScreen(loginId: loginId, isLoggedIn: isLoggedIn),
      ReviewListScreen(isLoggedIn: isLoggedIn, loginId: loginId),
      MyPageScreen(
        isLoggedIn: isLoggedIn,
        userName: userName,
        loginId: loginId,
        onLoginSuccess: onLoginSuccess,
        onSignUpTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SignUpScreen(onSuccess: onLoginSuccess),
          ),
        ),
        onLogout: () => setState(() {
          isLoggedIn = false;
          userName = "";
          loginId = "";
          globalScrapList.clear();
        }),
      ),
    ];

      return Scaffold(
        body: screens[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.deepOrange,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: '검색'),
            BottomNavigationBarItem(icon: Icon(Icons.favorite), label: '스크랩'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt), label: '후기'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'MY'),
          ],
        ),
      );
    }
  }



// ---------------------------------------------------------
// 2. 홈 화면 (자동 슬라이드 배너 + 공유 레시피 그리드)
// ---------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final bool isLoggedIn;
  final String loginId;
  final String userName;

  const HomeScreen({
    super.key,
    required this.isLoggedIn,
    required this.loginId,
    required this.userName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CollectionReference<Map<String, dynamic>> _recipesRef =
      FirebaseFirestore.instance.collection('recipe_list');
  
  // PageController를 클래스 변수로 선언하여 PageView에서 공유합니다.
  final PageController _bannerController = PageController(viewportFraction: 0.85);
  
  Timer? _bannerTimer;
  int _bannerPage = 0;
  List<Map<String, dynamic>> _bannerRecipes = [];

@override
void initState() {
  super.initState();
  _loadBannerRecipes().then((_){
    if (mounted) {
      _startBannerTimer();
    }
  });
}

// 타이머 시작 함수
void _startBannerTimer() {
  _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
    if (_bannerRecipes.isNotEmpty && _bannerController.hasClients) {
      int nextPage = (_bannerPage + 1) % _bannerRecipes.length;
      _bannerController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  });
}

@override
void dispose() {
  _bannerTimer?.cancel(); // 페이지 종료 시 타이머 해제 (중요!)
  _bannerController.dispose();
  super.dispose();
}

  // 예시용 로드 함수 (실제 환경에 맞게 수정하여 사용하세요)
Future<void> _loadBannerRecipes() async {
  try {
    // 1. 추천 관리 컬렉션에서 'today' 문서 가져오기
    DocumentSnapshot meta = await FirebaseFirestore.instance
        .collection('daily_recommendations')
        .doc('today')
        .get();

    // 2. 문서가 존재하고 today_ids 배열이 있는지 확인
    if (meta.exists && meta.data() != null) {
      Map<String, dynamic> data = meta.data() as Map<String, dynamic>;
      List<dynamic> ids = data['today_ids'] ?? [];

      if (ids.isNotEmpty) {
        // 3. 해당 ID 리스트에 있는 레시피만 가져오기
        QuerySnapshot snapshot = await FirebaseFirestore.instance
            .collection('recipes')
            .where(FieldPath.documentId, whereIn: ids)
            .get();

        if (mounted) {
          setState(() {
            _bannerRecipes = snapshot.docs
                .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
                .toList();
          });
        }
      }
    }
  } catch (e) {
    debugPrint("추천 레시피 로드 실패: $e");
  }
}

  Future<void> _toggleScrap(Map<String, dynamic> recipe) async {
    if (!widget.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스크랩은 로그인 후에 가능합니다.')));
      return;
    }
    setState(() {
      bool isScrapped = globalScrapList.any((item) => item['recipe_food'] == recipe['recipe_food']);
      if (isScrapped) {
        globalScrapList.removeWhere((item) => item['recipe_food'] == recipe['recipe_food']);
      } else {
        globalScrapList.add(recipe);
      }
    });
    try {
        await FirebaseFirestore.instance.collection('users').doc(widget.loginId).update({
          'scraps': globalScrapList,
        });
      } catch (e) {
        debugPrint("스크랩 저장 실패: $e");
        // 실패 시 사용자에게 알림을 줄 수도 있습니다.
      }
    }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Text('Team Cook', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black)),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Row(
                  children: [
                    const Expanded(child: Divider(color: Colors.deepOrange, thickness: 1.5, endIndent: 10)),
                    const Text('오늘의 추천 메뉴', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    const Expanded(child: Divider(color: Colors.deepOrange, thickness: 1.5, indent: 10)),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildRecommendBanner()),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 15),
                child: Text('공유 레시피', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey)),
              ),
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _recipesRef.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SliverToBoxAdapter(child: SizedBox());
                final recipes = snapshot.data!.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _recipeCard(context, recipes[index]),
                      childCount: recipes.length,
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.85,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepOrange,
        onPressed: () {
          if (!widget.isLoggedIn) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('레시피 등록은 로그인 후에 가능합니다.')));
            return;
          }
          Navigator.push(context, MaterialPageRoute(builder: (context) => RecipeFormScreen(loginId: widget.loginId, ownerId: widget.loginId, ownerName: widget.userName)));
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildRecommendBanner() {
    if (_bannerRecipes.isEmpty) return const SizedBox(height: 350);
    return Column(
      children: [
        SizedBox(
          height: 350,
          child: PageView.builder(
            controller: _bannerController,
            onPageChanged: (page) => setState(() => _bannerPage = page),
            itemCount: _bannerRecipes.length,
            itemBuilder: (context, index) => _bannerCard(_bannerRecipes[index]),
          ),
        ),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_bannerRecipes.length, (i) => 
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _bannerPage == i ? 16 : 6, height: 6,
              decoration: BoxDecoration(color: _bannerPage == i ? Colors.deepOrange : Colors.grey.shade300, borderRadius: BorderRadius.circular(3))
            )
          ),
        ),
      ],
    );
  }

  Widget _bannerCard(Map<String, dynamic> recipe) {
    bool isScrapped = globalScrapList.any((item) => item['recipe_food'] == recipe['recipe_food']);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => RecipeDetailScreen(recipe: recipe, currentUserId: widget.loginId, isLoggedIn: widget.isLoggedIn))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 4))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(recipe['imageUrl'] ?? recipe['url'] ?? 'https://picsum.photos/400/300', fit: BoxFit.cover),
              Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.55)]))),
              Positioned(left: 16, right: 16, bottom: 16, child: Text(recipe['recipe_food']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
              Positioned(top: 10, right: 10, child: GestureDetector(onTap: () => _toggleScrap(recipe), child: Icon(isScrapped ? Icons.favorite : Icons.favorite_border, color: isScrapped ? Colors.red : Colors.white, size: 28))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recipeCard(BuildContext context, Map<String, dynamic> recipe) {
    bool isScrapped = globalScrapList.any((item) => item['recipe_food'] == recipe['recipe_food']);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => RecipeDetailScreen(recipe: recipe, currentUserId: widget.loginId, isLoggedIn: widget.isLoggedIn))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(recipe['imageUrl'] ?? recipe['url'] ?? 'https://picsum.photos/400/300', fit: BoxFit.cover, width: double.infinity)),
                Positioned(top: 5, right: 5, child: GestureDetector(onTap: () => _toggleScrap(recipe), child: Icon(isScrapped ? Icons.favorite : Icons.favorite_border, color: isScrapped ? Colors.red : Colors.white, size: 20))),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(recipe['recipe_food']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(recipe['category']?.toString() ?? '분류 없음', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}
// ---------------------------------------------------------
// 검색 화면 (인기 검색어 + 최근 검색어 + 검색 결과)
// ---------------------------------------------------------
class SearchScreen extends StatefulWidget {
  final bool isLoggedIn;
  final String loginId;

  const SearchScreen({
    super.key,
    required this.isLoggedIn,
    required this.loginId,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final CollectionReference<Map<String, dynamic>> _recipesRef =
      FirebaseFirestore.instance.collection('recipe_list');

  String _searchQuery = '';
  bool _isSearching = false;

  static final List<String> _recentSearches = [];

  final List<String> _categories = ['전체', '한식', '중식', '일식', '양식', '기타'];
  String _selectedCategory = '전체';

  final List<String> _popularKeywords = [
    '김치찌개',
    '된장찌개',
    '불고기',
    '파스타',
    '볶음밥',
    '계란말이',
    '라면',
    '닭갈비',
    '순두부찌개',
    '비빔밥',
  ];

  void _submitSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _recentSearches.remove(trimmed);
    _recentSearches.insert(0, trimmed);
    if (_recentSearches.length > 10) _recentSearches.removeLast();
    setState(() {
      _searchQuery = trimmed;
      _isSearching = true;
    });
    _focusNode.unfocus();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _isSearching = false;
    });
  }

  void _removeRecentKeyword(String keyword) {
    setState(() => _recentSearches.remove(keyword));
  }

  bool _matchRecipe(Map<String, dynamic> recipe) {
    final query = _searchQuery.trim().toLowerCase();
    final category = recipe['category']?.toString() ?? '';
    final categoryMatch =
        _selectedCategory == '전체' || category == _selectedCategory;

    if (_isSearching) {
      if (query.isEmpty) return false;
      final name =
          recipe['recipe_food']?.toString().toLowerCase() ??
          recipe['name']?.toString().toLowerCase() ??
          '';
      final ingredients = (recipe['ingredients'] is List)
          ? (recipe['ingredients'] as List).join(' ').toLowerCase()
          : recipe['ingredients']?.toString().toLowerCase() ?? '';
      return categoryMatch &&
          (name.contains(query) || ingredients.contains(query));
    }
    return categoryMatch;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _submitSearch,
                      onChanged: (v) {
                        if (v.trim().isEmpty && _isSearching) {
                          setState(() {
                            _searchQuery = '';
                            _isSearching = false;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        hintText: '요리, 재료를 검색해주세요.',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _clearSearch,
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (_isSearching) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _clearSearch,
                      child: const Text(
                        '취소',
                        style: TextStyle(color: Colors.deepOrange),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _categories.map((category) {
                  final selected = category == _selectedCategory;
                  return ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    selectedColor: Colors.deepOrange,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontSize: 13,
                    ),
                    onSelected: (_) {
                      setState(() => _selectedCategory = category);
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _isSearching ? _buildResults() : _buildSuggestions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text(
            '🔥 인기 검색어',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularKeywords.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final keyword = entry.value;
              return GestureDetector(
                onTap: () {
                  _searchController.text = keyword;
                  _submitSearch(keyword);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade100,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: rank <= 3 ? Colors.deepOrange : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(keyword, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_recentSearches.isNotEmpty) ...[
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🕐 최근 검색어',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => setState(() => _recentSearches.clear()),
                  child: const Text(
                    '전체 삭제',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ..._recentSearches.map(
              (keyword) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, color: Colors.grey),
                title: Text(keyword, style: const TextStyle(fontSize: 14)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                  onPressed: () => _removeRecentKeyword(keyword),
                ),
                onTap: () {
                  _searchController.text = keyword;
                  _submitSearch(keyword);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResults() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _recipesRef.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('데이터 로드 중 오류가 발생했습니다.'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final results = docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .where(_matchRecipe)
            .toList();

        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  '"$_searchQuery" 검색 결과가 없습니다.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '"$_searchQuery" 검색 결과 ${results.length}건',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 15,
                  crossAxisSpacing: 15,
                  childAspectRatio: 0.75,
                ),
                itemCount: results.length,
                itemBuilder: (context, index) {
                  return _searchResultCard(context, results[index]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _searchResultCard(BuildContext context, Map<String, dynamic> recipe) {
    bool isScrapped = globalScrapList.any(
      (item) => item['recipe_food'] == recipe['recipe_food'],
    );
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RecipeDetailScreen(
              recipe: recipe,
              currentUserId: widget.loginId,
              isLoggedIn: widget.isLoggedIn,
            ),
          ),
        );
        setState(() {});
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    child: Image.network(
                      recipe['imageUrl'] ??
                          recipe['url'] ??
                          'https://picsum.photos/400/300',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.image_not_supported),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        if (!widget.isLoggedIn) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('로그인 후 이용 가능합니다.')),
                          );
                          return;
                        }
                        setState(() {
                          if (isScrapped) {
                            globalScrapList.removeWhere(
                              (item) =>
                                  item['recipe_food'] == recipe['recipe_food'],
                            );
                          } else {
                            globalScrapList.add(recipe);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isScrapped ? Icons.favorite : Icons.favorite_border,
                          color: isScrapped ? Colors.red : Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe['recipe_food']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    recipe['category']?.toString() ?? '분류 없음',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.orange, size: 14),
                      Text(
                        ' ${recipe['averageRating']?.toStringAsFixed(1) ?? recipe['score']?.toString() ?? '0.0'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '난이도: ${recipe['difficulty'] ?? recipe['level'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// RecipeFormScreen
// ---------------------------------------------------------
class RecipeFormScreen extends StatefulWidget {
  final String ownerId;
  final String ownerName;
  final String? recipeId;
  final String loginId;
  final Map<String, dynamic>? initialData;

  const RecipeFormScreen({
    super.key,
    required this.ownerId,
    required this.ownerName,
    required this.loginId,
    this.recipeId,
    this.initialData,
  });

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController(
    text: 'https://picsum.photos/400/300',
  );
  final _timeController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _servingsController = TextEditingController();
  String _level = '쉬움';
  String _category = '한식';
  final _ingredientsController = TextEditingController();
  final List<TextEditingController> _stepDescControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<TextEditingController> _stepTimeControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void initState() {
    super.initState();
    final initialData = widget.initialData;
    if (initialData != null) {
      _nameController.text =
          initialData['recipe_food']?.toString() ??
          initialData['name']?.toString() ??
          '';
      _urlController.text =
          initialData['imageUrl']?.toString() ??
          'https://picsum.photos/400/300';
      _timeController.text =
          initialData['cook_time']?.toString().replaceAll(
            RegExp(r'[^0-9]'),
            '',
          ) ??
          '';
      _caloriesController.text =
          initialData['calories']?.toString().replaceAll('Kcal', '').trim() ??
          '';
      _servingsController.text = initialData['servings']?.toString() ?? '';
      _level = initialData['difficulty']?.toString() ?? _level;
      _category = initialData['category']?.toString() ?? _category;

      final ingredients = initialData['ingredients'];
      if (ingredients is String) {
        _ingredientsController.text = ingredients;
      } else if (ingredients is List) {
        _ingredientsController.text = ingredients
            .map((e) => e.toString())
            .join(', ');
      }

      final stepsData = initialData['steps'];
      if (stepsData != null) {
        List<Map<String, dynamic>> stepsList = [];
        if (stepsData is List) {
          for (final item in stepsData) {
            if (item is Map) {
              stepsList.add({
                'desc': item['desc']?.toString() ?? '',
                'time': item['time'] is int
                    ? item['time']
                    : int.tryParse(item['time']?.toString() ?? '0') ?? 0,
              });
            }
          }
        } else if (stepsData is String && stepsData.isNotEmpty) {
          final lines = stepsData
              .split(RegExp(r'(?=\d+\.)'))
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();
          for (final line in lines) {
            final desc = line.replaceFirst(RegExp(r'^\d+\.\s*'), '');
            stepsList.add({'desc': desc, 'time': 0});
          }
        }

        if (stepsList.isNotEmpty) {
          for (final c in _stepDescControllers) c.dispose();
          for (final c in _stepTimeControllers) c.dispose();
          _stepDescControllers.clear();
          _stepTimeControllers.clear();

          for (final step in stepsList) {
            var desc = step['desc']?.toString() ?? '';
            desc = desc.replaceFirst(RegExp(r'^\d+\.\s*'), '');
            final timeSeconds = step['time'] ?? 0;
            final minutes = (timeSeconds as int) ~/ 60;
            _stepDescControllers.add(TextEditingController(text: desc));
            _stepTimeControllers.add(
              TextEditingController(
                text: minutes > 0 ? minutes.toString() : '',
              ),
            );
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _timeController.dispose();
    _caloriesController.dispose();
    _servingsController.dispose();
    _ingredientsController.dispose();
    for (final c in _stepDescControllers) c.dispose();
    for (final c in _stepTimeControllers) c.dispose();
    super.dispose();
  }

  void _addStep() {
    setState(() {
      _stepDescControllers.add(TextEditingController());
      _stepTimeControllers.add(TextEditingController());
    });
  }

  void _removeStep(int index) {
    if (_stepDescControllers.length <= 1) return;
    setState(() {
      _stepDescControllers[index].dispose();
      _stepTimeControllers[index].dispose();
      _stepDescControllers.removeAt(index);
      _stepTimeControllers.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final ingredients = _ingredientsController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final stepItems = <Map<String, dynamic>>[];
    for (var i = 0; i < _stepDescControllers.length; i++) {
      final desc = _stepDescControllers[i].text.trim();
      if (desc.isEmpty) continue;
      final seconds = int.tryParse(_stepTimeControllers[i].text.trim()) ?? 0;
      stepItems.add({'desc': desc, 'time': seconds});
    }

    if (ingredients.isEmpty || stepItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('재료와 조리 순서를 모두 입력해주세요.')));
      return;
    }

    final formattedSteps = stepItems
        .asMap()
        .entries
        .map(
          (entry) => {
            'desc': '${entry.key + 1}. ${entry.value['desc']}',
            'time': entry.value['time'] ?? 0,
          },
        )
        .toList();

    final ingredientsText = ingredients.join(', ');
    final recipesRef = FirebaseFirestore.instance.collection('recipe_list');
    final doc = widget.recipeId != null
        ? recipesRef.doc(widget.recipeId)
        : recipesRef.doc();

    final caloriesValue = _caloriesController.text.trim();
    final caloriesFormatted = caloriesValue.isEmpty
        ? ''
        : (caloriesValue.contains('Kcal')
              ? caloriesValue
              : '${caloriesValue}Kcal');

    final Map<String, dynamic> data = {
      'recipe_food': _nameController.text.trim(),
      'imageUrl': _urlController.text.trim(),
      'category': _category,
      'calories': caloriesFormatted,
      'cook_time': '${_timeController.text.trim()}분',
      'difficulty': _level,
      'servings': _servingsController.text.trim(),
      'ingredients': ingredientsText,
      'steps': formattedSteps,
      'ownerId': widget.ownerId,
      'ownerName': widget.ownerName,
    };

    if (widget.recipeId == null) {
      data.addAll({
        'averageRating': 0.0,
        'ratingCount': 0,
        'reviewCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await doc.set(data);

        await earnPoints(widget.loginId, 100); 

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('레시피가 등록되었습니다! (+100 P)',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: Colors.deepOrange,
              duration: Duration(seconds: 2), // 메시지가 떠 있는 시간
            ),
          );
        }
    }
     else {
      await doc.set(data, SetOptions(merge: true));
    }

    if (!mounted) return;
    Navigator.pop(context, data);
  }


  @override
Widget build(BuildContext context) {
  final title = widget.recipeId == null ? '레시피 등록' : '레시피 수정';
  
  return Scaffold(
    appBar: AppBar(
      title: Text(
        title, 
        style: const TextStyle(
          color: Colors.white,        // 글자 색상을 흰색으로!
          fontWeight: FontWeight.bold, // 더 선명하게 굵게 처리
        ),
      ), 
      backgroundColor: Colors.deepOrange,
      iconTheme: const IconThemeData(color: Colors.white), // 뒤로가기 버튼(화살표)도 흰색으로 변경
    ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '레시피 이름'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '레시피 이름을 입력해주세요.' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(labelText: '대표 이미지 URL'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '대표 이미지를 입력해주세요.' : null,
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _timeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '총 소요 시간(분)',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? '총 시간을 입력해주세요.'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _servingsController,
                      decoration: const InputDecoration(
                        labelText: '분량 (예: 2인분)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _category,
                      decoration: const InputDecoration(labelText: '카테고리'),
                      items: const [
                        DropdownMenuItem(value: '한식', child: Text('한식')),
                        DropdownMenuItem(value: '중식', child: Text('중식')),
                        DropdownMenuItem(value: '일식', child: Text('일식')),
                        DropdownMenuItem(value: '양식', child: Text('양식')),
                        DropdownMenuItem(value: '기타', child: Text('기타')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _category = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _caloriesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '칼로리 (선택)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: _level,
                decoration: const InputDecoration(labelText: '난이도'),
                items: const [
                  DropdownMenuItem(value: '쉬움', child: Text('쉬움')),
                  DropdownMenuItem(value: '보통', child: Text('보통')),
                  DropdownMenuItem(value: '어려움', child: Text('어려움')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _level = v);
                },
              ),
              const SizedBox(height: 20),
              const Text(
                '준비 재료',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ingredientsController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '재료를 한 줄에 하나씩 입력하세요.',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '재료를 입력해주세요.' : null,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '조리 순서',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  TextButton(onPressed: _addStep, child: const Text('+ 단계 추가')),
                ],
              ),
              const SizedBox(height: 10),
              ...List.generate(_stepDescControllers.length, (index) {
                return Column(
                  children: [
                    TextFormField(
                      controller: _stepDescControllers[index],
                      decoration: InputDecoration(
                        labelText: 'Step ${index + 1} 설명',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '설명을 입력해주세요.' : null,
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {

                        Duration selected = Duration(
                          seconds: int.tryParse(
                            _stepTimeControllers[index].text
                          ) ?? 0,
                        );

                        showModalBottomSheet(
                          context: context,

                          builder: (context) {

                            return SizedBox(
                              height: 300,

                              child: CupertinoTimerPicker(

                                mode: CupertinoTimerPickerMode.ms,

                                initialTimerDuration: selected,

                                onTimerDurationChanged: (value) {

                                  setState(() {

                                    _stepTimeControllers[index].text =
                                        value.inSeconds.toString();

                                  });

                                },

                              ),

                            );

                          },
                        );

                      },

                      child: AbsorbPointer(

                        child: TextFormField(

                          controller: _stepTimeControllers[index],

                          decoration: const InputDecoration(
                            labelText: '타이머 설정 (눌러서 선택)',
                            suffixIcon: Icon(Icons.timer),
                          ),

                        ),

                      ),

                    ),
                    if (_stepDescControllers.length > 1)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _removeStep(index),
                          child: const Text(
                            '단계 제거',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    const Divider(),
                  ],
                );
              }),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                  ),
                  child: Text(
                    widget.recipeId == null ? '레시피 등록 하기' : '수정 저장',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 3. 스크랩 화면
// ---------------------------------------------------------
class ScrapScreen extends StatefulWidget {
  final String loginId;
  final bool isLoggedIn;

  const ScrapScreen({
    super.key,
    required this.loginId,
    required this.isLoggedIn,
  });

  @override
  State<ScrapScreen> createState() => _ScrapScreenState();
}

class _ScrapScreenState extends State<ScrapScreen> {
  void _refresh() => setState(() {});

  Future<void> _removeScrap(Map<String, dynamic> recipe) async {
    setState(() {
      globalScrapList.removeWhere(
        (item) =>
            (item['recipe_food'] ?? item['name']) ==
            (recipe['recipe_food'] ?? recipe['name']),
      );
    });
    if (widget.isLoggedIn && widget.loginId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.loginId)
            .update({'scraps': globalScrapList});
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '내 스크랩 레시피',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: globalScrapList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '아직 스크랩한 레시피가 없어요!',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 0.75,
              ),
              itemCount: globalScrapList.length,
              itemBuilder: (context, index) {
                final recipe = globalScrapList[index];
                return _buildScrapCard(context, recipe);
              },
            ),
    );
  }

  Widget _buildScrapCard(BuildContext context, Map<String, dynamic> recipe) {
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RecipeDetailScreen(
              recipe: recipe,
              currentUserId: widget.loginId,
              isLoggedIn: widget.isLoggedIn,
            ),
          ),
        );
        _refresh();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    child: Image.network(
                      recipe['imageUrl'] ??
                          recipe['url'] ??
                          'https://picsum.photos/400/300',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.image_not_supported),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _removeScrap(recipe),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                recipe['recipe_food'] ?? recipe['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 4. 레시피 상세
// ---------------------------------------------------------
class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final String currentUserId;
  final bool isLoggedIn;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.currentUserId,
    required this.isLoggedIn,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  Timer? _timer;

  int _remainingSeconds = 0;

  bool _isTimerActive = false;
  
  List<String> get ingredients {
    final raw = widget.recipe['ingredients'];
    if (raw is String) {
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is List) return List<String>.from(raw);
    return [];
  }

  List<Map<String, dynamic>> get steps {
    final raw = widget.recipe['steps'];
    if (raw is List) {
      return raw
          .expand((item) => _parseStepItems(item))
          .where((s) => (s['desc'] as String).isNotEmpty)
          .toList();
    }
    if (raw is String) return _parseStepString(raw);
    return [];
  }

  Iterable<Map<String, dynamic>> _parseStepItems(dynamic item) {
    if (item is Map) {
      return [
        {
          'desc': item['desc']?.toString() ?? item['step']?.toString() ?? '',
          'time': item['time'] is int
              ? item['time']
              : int.tryParse(item['time']?.toString() ?? '0') ?? 0,
        },
      ];
    }
    if (item is String) return _parseStepString(item);
    return [];
  }

  List<Map<String, dynamic>> _parseStepString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return [];
    final splitResults = raw
        .split(RegExp(r'(?=\d+\.)'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (splitResults.length == 1) {
      return [
        {
          'desc': splitResults.first,
          'time': _extractTimeFromDesc(splitResults.first),
        },
      ];
    }
    return splitResults
        .map((desc) => {'desc': desc, 'time': _extractTimeFromDesc(desc)})
        .toList();
  }

  int _extractTimeFromDesc(String desc) {
    final match = RegExp(r'(\d+)\s*분').firstMatch(desc);
    if (match != null) {
      final value = int.tryParse(match.group(1) ?? '');
      return value != null ? value * 60 : 0;
    }
    return 0;
  }

  final TextEditingController _reviewController = TextEditingController();
  int _reviewRating = 5;
  bool _isEditingReview = false;
  String? _editingReviewId;
  Map<String, dynamic>? _editingReview;

  CollectionReference<Map<String, dynamic>> get _reviewsRef {
    final recipeId = widget.recipe['id']?.toString();
    return FirebaseFirestore.instance
        .collection('recipe_list')
        .doc(recipeId)
        .collection('reviews');
  }

  // ★ 핵심 수정: isLoggedIn prop을 직접 사용
  bool get _isLoggedIn => widget.isLoggedIn && widget.currentUserId.isNotEmpty;

  // ★ 스크랩 토글 - 비로그인 차단 완벽 처리
  Future<void> _toggleScrap() async {
    if (!_isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인 후 이용 가능합니다.')));
      return;
    }

    final recipeName =
        widget.recipe['recipe_food'] ?? widget.recipe['name'] ?? '';
    final bool isScrapped = globalScrapList.any(
      (item) => (item['recipe_food'] ?? item['name']) == recipeName,
    );

    setState(() {
      if (isScrapped) {
        globalScrapList.removeWhere(
          (item) => (item['recipe_food'] ?? item['name']) == recipeName,
        );
      } else {
        globalScrapList.add(widget.recipe);
      }
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .update({'scraps': globalScrapList});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isScrapped ? '스크랩이 해제되었습니다.' : '스크랩되었습니다!')),
      );
    } catch (_) {}
  }

  Future<void> _submitReview() async {
    if (!_isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인 후 이용해주세요.')));
      return;
    }

    final content = _reviewController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('댓글을 입력해주세요.')));
      return;
    }

    final recipeId = widget.recipe['id']?.toString();
    if (recipeId == null || recipeId.isEmpty) return;

    final recipeRef = FirebaseFirestore.instance
        .collection('recipe_list')
        .doc(recipeId);
    final rating = _reviewRating.clamp(1, 5);
    final currentAvg =
        (widget.recipe['averageRating'] as num?)?.toDouble() ?? 0.0;
    final currentCount = (widget.recipe['ratingCount'] is int)
        ? widget.recipe['ratingCount'] as int
        : (widget.recipe['reviewCount'] is int
              ? widget.recipe['reviewCount'] as int
              : 0);

    late final double newAvg;
    final newCount = _isEditingReview ? currentCount : currentCount + 1;
    if (_isEditingReview) {
      final oldRating = _editingReview?['rating'] is int
          ? _editingReview!['rating'] as int
          : int.tryParse(_editingReview?['rating']?.toString() ?? '') ?? rating;
      newAvg = currentCount > 0
          ? ((currentAvg * currentCount) - oldRating + rating) / currentCount
          : rating.toDouble();
    } else {
      newAvg = newCount > 0
          ? ((currentAvg * currentCount) + rating) / newCount
          : rating.toDouble();
    }

    final reviewRef = _isEditingReview && _editingReviewId != null
        ? _reviewsRef.doc(_editingReviewId)
        : _reviewsRef.doc();

    final reviewData = {
      'authorId': widget.currentUserId,
      'authorName': widget.currentUserId,
      'content': content,
      'rating': rating,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = FirebaseFirestore.instance.batch();
    if (_isEditingReview) {
      batch.update(reviewRef, reviewData);
    } else {
      batch.set(reviewRef, reviewData);
    }
    batch.update(recipeRef, {
      'averageRating': newAvg,
      'ratingCount': newCount,
      'reviewCount': newCount,
    });
    await batch.commit();

    if (!_isEditingReview) {
      await earnPoints(widget.currentUserId, 1);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('댓글이 작성되었습니다! (+1 P)',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: Colors.deepOrange,
              duration: Duration(seconds: 2),
          ),
        );
      }
    }

    setState(() {
      widget.recipe['averageRating'] = newAvg;
      widget.recipe['ratingCount'] = newCount;
      widget.recipe['reviewCount'] = newCount;
      _reviewController.clear();
      _reviewRating = 5;
      _isEditingReview = false;
      _editingReviewId = null;
      _editingReview = null;
    });
  }

  Future<void> _startEditingReview(
    Map<String, dynamic> review,
    String reviewId,
  ) async {
    setState(() {
      _isEditingReview = true;
      _editingReviewId = reviewId;
      _editingReview = review;
      _reviewController.text = review['content']?.toString() ?? '';
      _reviewRating = review['rating'] is int
          ? review['rating'] as int
          : int.tryParse(review['rating']?.toString() ?? '') ?? 5;
    });
  }

  Future<void> _deleteReview(String reviewId, int rating) async {
    final recipeId = widget.recipe['id']?.toString();
    if (recipeId == null || recipeId.isEmpty) return;

    final recipeRef = FirebaseFirestore.instance
        .collection('recipe_list')
        .doc(recipeId);
    final currentAvg =
        (widget.recipe['averageRating'] as num?)?.toDouble() ?? 0.0;
    final currentCount = (widget.recipe['ratingCount'] is int)
        ? widget.recipe['ratingCount'] as int
        : (widget.recipe['reviewCount'] is int
              ? widget.recipe['reviewCount'] as int
              : 0);
    final newCount = currentCount > 0 ? currentCount - 1 : 0;
    final newAvg = newCount > 0
        ? ((currentAvg * currentCount) - rating) / newCount
        : 0.0;

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_reviewsRef.doc(reviewId));
    batch.update(recipeRef, {
      'averageRating': newAvg,
      'ratingCount': newCount,
      'reviewCount': newCount,
    });
    await batch.commit();

    setState(() {
      widget.recipe['averageRating'] = newAvg;
      widget.recipe['ratingCount'] = newCount;
      widget.recipe['reviewCount'] = newCount;
      if (_editingReviewId == reviewId) {
        _isEditingReview = false;
        _editingReviewId = null;
        _editingReview = null;
        _reviewController.clear();
        _reviewRating = 5;
      }
    });
  }

  Widget _buildReviewStars({
    required int rating,
    required void Function(int) onChanged,
  }) {
    return Row(
      children: List.generate(5, (index) {
        final value = index + 1;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            value <= rating ? Icons.star : Icons.star_border,
            color: Colors.amber,
          ),
          onPressed: () => onChanged(value),
        );
      }),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review, String reviewId) {
    final authorId = review['authorId']?.toString() ?? '';
    final authorName = review['authorName']?.toString() ?? authorId;
    final content = review['content']?.toString() ?? '';
    final rating = review['rating'] is int
        ? review['rating'] as int
        : int.tryParse(review['rating']?.toString() ?? '') ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.deepOrange.shade100,
                child: Text(
                  authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  authorName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 18,
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(content, style: const TextStyle(fontSize: 15, height: 1.4)),
          if (authorId == widget.currentUserId) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => _startEditingReview(review, reviewId),
                  child: const Text('수정'),
                ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('댓글 삭제'),
                        content: const Text('정말 이 댓글을 삭제하시겠습니까?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('취소'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text(
                              '삭제',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true)
                      await _deleteReview(reviewId, rating);
                  },
                  child: const Text('삭제', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() => _isTimerActive = false);
  }

  String _formatTime(int seconds) {
    final m = (seconds / 60).floor().toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m : $s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reviewController.dispose();
    super.dispose();
  }

  void _startTimer(int seconds) {

    _timer?.cancel();

    setState(() {
      _remainingSeconds = seconds;
      _isTimerActive = true;
    });


    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {

        if (_remainingSeconds <= 0) {

          timer.cancel();

          setState(() {
            _isTimerActive = false;
          });

          return;
        }


        setState(() {
          _remainingSeconds--;
        });

      },
    );
  }
  @override
  Widget build(BuildContext context) {
    final recipeName =
        widget.recipe['recipe_food'] ?? widget.recipe['name'] ?? '';
    final bool isScrapped = globalScrapList.any(
      (item) => (item['recipe_food'] ?? item['name']) == recipeName,
    );
    final bool isOwner =
        _isLoggedIn && widget.recipe['ownerId'] == widget.currentUserId;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.deepOrange),
                actions: [
                  IconButton(
                    icon: Icon(
                      isScrapped ? Icons.favorite : Icons.favorite_border,
                      color: isScrapped ? Colors.red : Colors.deepOrange,
                    ),
                    onPressed: _toggleScrap,
                  ),
                  if (isOwner) ...[
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.deepOrange),
                      onPressed: () async {
                        final updated =
                            await Navigator.push<Map<String, dynamic>>(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RecipeFormScreen(
                                  loginId: widget.currentUserId,
                                  ownerId: widget.currentUserId,
                                  ownerName: widget.recipe['ownerName'] ?? '',
                                  recipeId: widget.recipe['id']?.toString(),
                                  initialData: widget.recipe,
                                ),
                              ),
                            );
                        if (updated != null) {
                          setState(() => widget.recipe.addAll(updated));
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('레시피 삭제'),
                            content: const Text('정말 이 레시피를 삭제하시겠습니까?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('취소'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  '삭제',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          final recipeId = widget.recipe['id']?.toString();
                          if (recipeId != null && recipeId.isNotEmpty) {
                            final recipeRef = FirebaseFirestore.instance
                                .collection('recipe_list')
                                .doc(recipeId);
                            final reviewsSnapshot = await recipeRef
                                .collection('reviews')
                                .get();
                            final batch = FirebaseFirestore.instance.batch();
                            for (final d in reviewsSnapshot.docs) {
                              batch.delete(d.reference);
                            }
                            batch.delete(recipeRef);
                            await batch.commit();
                            if (!mounted) return;
                            Navigator.pop(context);
                          }
                        }
                      },
                    ),
                  ],
                ],
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    widget.recipe['recipe_food'] ?? widget.recipe['name'] ?? '',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        widget.recipe['imageUrl'] ??
                            widget.recipe['url'] ??
                            'https://picsum.photos/400/300',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.image_not_supported),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.white.withOpacity(0.8),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildInfoBadge(
                            Icons.timer,
                            widget.recipe['cook_time']?.toString() ?? '시간 미정',
                          ),
                          _buildInfoBadge(
                            Icons.star,
                            '${widget.recipe['averageRating']?.toStringAsFixed(1) ?? widget.recipe['score']?.toString() ?? '0.0'}점',
                          ),
                          _buildInfoBadge(
                            Icons.restaurant,
                            widget.recipe['difficulty']?.toString() ??
                                widget.recipe['level']?.toString() ??
                                '쉬움',
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        '준비 재료',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade200,
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: ingredients
                              .map(
                                (ing) => Chip(
                                  label: Text(ing),
                                  backgroundColor: Colors.orange.shade50,
                                  side: BorderSide.none,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        '조리 순서',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      ...List.generate(steps.length, (index) {
                        final step = steps[index];
                        final stepTime = step['time'] is int
                            ? step['time'] as int
                            : int.tryParse(step['time']?.toString() ?? '0') ??
                                  0;
                        return _buildStepCard(
                          index + 1,
                          step['desc']?.toString() ?? '',
                          stepTime,
                        );
                      }),
                      const SizedBox(height: 30),
                      const Text(
                        '댓글 및 평점',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _reviewsRef
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Text('댓글을 불러오는 중 오류가 발생했습니다.');
                          }
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text(
                                '첫 댓글을 남겨보세요!',
                                style: TextStyle(color: Colors.grey),
                              ),
                            );
                          }
                          return Column(
                            children: docs
                                .map(
                                  (doc) => _buildReviewCard(doc.data(), doc.id),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 25),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '별점',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                _buildReviewStars(
                                  rating: _reviewRating,
                                  onChanged: (v) =>
                                      setState(() => _reviewRating = v),
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _reviewController,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText: _isLoggedIn
                                    ? '댓글을 입력해주세요.'
                                    : '로그인 후 댓글을 남길 수 있습니다.',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                              ),
                              enabled: _isLoggedIn,
                            ),
                            const SizedBox(height: 15),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoggedIn ? _submitReview : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepOrange,
                                  disabledBackgroundColor: Colors.grey.shade300,
                                ),
                                child: Text(
                                  _isEditingReview ? '댓글 수정' : '댓글 등록',
                                  style: const TextStyle(
                                    color: Colors.white,         // 글자색: 흰색
                                    fontWeight: FontWeight.bold, // 강조를 위한 굵게 설정
                                  ),
                                ),
                              ),
                            ),
                            if (_isEditingReview)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isEditingReview = false;
                                    _editingReviewId = null;
                                    _editingReview = null;
                                    _reviewController.clear();
                                    _reviewRating = 5;
                                  });
                                },
                                child: const Text('수정 취소'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_isTimerActive)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(35),
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.deepOrange,
                    borderRadius: BorderRadius.circular(35),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.timer, color: Colors.white, size: 28),
                      Text(
                        _formatTime(_remainingSeconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      IconButton(
                        onPressed: _stopTimer,
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: Colors.deepOrange, size: 30),
        const SizedBox(height: 5),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStepCard(int stepNum, String desc, int timeSeconds) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Colors.deepOrange,
            radius: 15,
            child: Text(
              '$stepNum',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: const TextStyle(fontSize: 16, height: 1.5)),
                if (timeSeconds > 0) ...[
                  const SizedBox(height: 15),
                  InkWell(
                    onTap: () => _startTimer(timeSeconds),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 15,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(
                          color: Colors.deepOrange.withOpacity(0.5),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow,
                            color: Colors.deepOrange,
                            size: 18,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${_formatTime(timeSeconds)} 타이머 시작',
                            style: const TextStyle(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// 5. 요리후기 리스트
// ---------------------------------------------------------
class ReviewListScreen extends StatefulWidget {
  final bool isLoggedIn;
  final String loginId;

  const ReviewListScreen({
    super.key,
    required this.isLoggedIn,
    required this.loginId,
  });

  @override
  State<ReviewListScreen> createState() => _ReviewListScreenState();
}

class _ReviewListScreenState extends State<ReviewListScreen> {
  Stream<List<Map<String, dynamic>>>? _reviewsStream;

  @override
  void initState() {
    super.initState();
    if (widget.isLoggedIn && widget.loginId.isNotEmpty) {
      _reviewsStream = _myRecipesReviewsStream(widget.loginId);
    }
  }

  @override
  void didUpdateWidget(covariant ReviewListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoggedIn != oldWidget.isLoggedIn ||
        widget.loginId != oldWidget.loginId) {
      if (widget.isLoggedIn && widget.loginId.isNotEmpty) {
        _reviewsStream = _myRecipesReviewsStream(widget.loginId);
      } else {
        _reviewsStream = null;
      }
    }
  }

  Stream<List<Map<String, dynamic>>> _myRecipesReviewsStream(String loginId) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    StreamSubscription? recipesSubscription;
    final Map<String, StreamSubscription> reviewSubscriptions = {};
    final Map<String, List<Map<String, dynamic>>> reviewsByRecipe = {};

    recipesSubscription = FirebaseFirestore.instance
        .collection('recipe_list')
        .where('ownerId', isEqualTo: loginId)
        .snapshots()
        .listen(
          (recipesSnapshot) {
            final currentRecipeIds = recipesSnapshot.docs
                .map((doc) => doc.id)
                .toSet();
            final keysToRemove = reviewSubscriptions.keys
                .where((id) => !currentRecipeIds.contains(id))
                .toList();
            for (final key in keysToRemove) {
              reviewSubscriptions[key]?.cancel();
              reviewSubscriptions.remove(key);
              reviewsByRecipe.remove(key);
            }

            if (recipesSnapshot.docs.isEmpty) {
              if (!controller.isClosed) controller.add([]);
              return;
            }

            for (final recipeDoc in recipesSnapshot.docs) {
              final recipeId = recipeDoc.id;
              final recipeName =
                  recipeDoc.data()['recipe_food'] ??
                  recipeDoc.data()['name'] ??
                  '';

              if (!reviewSubscriptions.containsKey(recipeId)) {
                reviewSubscriptions[recipeId] = recipeDoc.reference
                    .collection('reviews')
                    .snapshots()
                    .listen((reviewsSnapshot) {
                      final reviewList = reviewsSnapshot.docs.map((doc) {
                        return {
                          'id': doc.id,
                          'recipeId': recipeId,
                          'recipeName': recipeName,
                          ...doc.data(),
                        };
                      }).toList();
                      reviewsByRecipe[recipeId] = reviewList;
                      final allReviews = reviewsByRecipe.values
                          .expand((x) => x)
                          .toList();
                      allReviews.sort((a, b) {
                        final aTime = a['createdAt'] as Timestamp?;
                        final bTime = b['createdAt'] as Timestamp?;
                        if (aTime == null && bTime == null) return 0;
                        if (aTime == null) return 1;
                        if (bTime == null) return -1;
                        return bTime.compareTo(aTime);
                      });
                      if (!controller.isClosed) controller.add(allReviews);
                    });
              }
            }
          },
          onError: (err) {
            if (!controller.isClosed) controller.addError(err);
          },
        );

    controller.onCancel = () {
      recipesSubscription?.cancel();
      for (final sub in reviewSubscriptions.values) sub.cancel();
    };

    return controller.stream;
  }

  Widget _buildReviewItem(BuildContext context, Map<String, dynamic> review) {
    final authorId = review['authorId']?.toString() ?? '';
    final authorName = review['authorName']?.toString() ?? authorId;
    final content = review['content']?.toString() ?? '';
    final rating = review['rating'] is int
        ? review['rating'] as int
        : int.tryParse(review['rating']?.toString() ?? '') ?? 0;
    final recipeName = review['recipeName']?.toString() ?? '레시피';
    final createdAt = review['createdAt'] as Timestamp?;

    String timeStr = '';
    if (createdAt != null) {
      final date = createdAt.toDate();
      timeStr = '${date.year}.${date.month}.${date.day}';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) =>
                const Center(child: CircularProgressIndicator()),
          );
          try {
            final recipeDoc = await FirebaseFirestore.instance
                .collection('recipe_list')
                .doc(review['recipeId'])
                .get();
            Navigator.pop(context);
            if (recipeDoc.exists) {
              final recipeData = {'id': recipeDoc.id, ...recipeDoc.data()!};
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RecipeDetailScreen(
                    recipe: recipeData,
                    currentUserId: widget.loginId,
                    isLoggedIn: widget.isLoggedIn,
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('존재하지 않거나 삭제된 레시피입니다.')),
              );
            }
          } catch (e) {
            Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('레시피 로드 오류: $e')));
          }
        },
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      recipeName,
                      style: const TextStyle(
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (timeStr.isNotEmpty)
                    Text(
                      timeStr,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.deepOrange.shade100,
                    child: Text(
                      authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    authorName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: List.generate(5, (index) {
                      return Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 14,
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '요리후기',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: !widget.isLoggedIn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '로그인 후 내가 등록한 레시피의 댓글을 확인할 수 있습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            )
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _reviewsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('데이터 로드 중 오류가 발생했습니다.'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final reviews = snapshot.data ?? [];
                if (reviews.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '내가 등록한 레시피에 아직 댓글이 없습니다.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: reviews.length,
                  itemBuilder: (context, index) =>
                      _buildReviewItem(context, reviews[index]),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------
// 6. 마이페이지
// ---------------------------------------------------------
class MyPageScreen extends StatelessWidget {
  final bool isLoggedIn;
  final String userName;
  final String loginId;
  final Function(String, String) onLoginSuccess;
  final VoidCallback onSignUpTap;
  final VoidCallback onLogout;

  const MyPageScreen({
    super.key,
    required this.isLoggedIn,
    required this.userName,
    required this.loginId,
    required this.onLoginSuccess,
    required this.onSignUpTap,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: !isLoggedIn
          ? LoginScreen(onLoginSuccess: onLoginSuccess, onSignUpTap: onSignUpTap)
          : _profilePage(context),
    );
  }

  Widget _profilePage(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(25),
            leading: const CircleAvatar(
              radius: 35,
              backgroundColor: Colors.deepOrange,
              child: Icon(Icons.person, color: Colors.white, size: 40),
            ),
            title: Text(
              '$userName님 안녕하세요!',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('팀쿡의 회원이 되신 걸 환영해요!'),
          ),
          _buildPointSection(), // 인자 없이 호출 가능
          const Divider(thickness: 10, color: Color(0xFFF8F8F8)),
          if (loginId == 'admin')
            ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Colors.red),
              title: const Text('관리자 전용: 회원 관리 메뉴', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.chevron_right, color: Colors.red),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminUserListScreen())),
            ),
          if (loginId == 'admin') const Divider(thickness: 1, color: Color(0xFFECECEC)),
          _menu(context, Icons.edit, '정보 변경', true),
          _menu(context, Icons.headset_mic, '고객센터', false),
          _menu(context, Icons.settings, '환경설정', false),
          _menu(context, Icons.info, '앱 정보', false),
          const Spacer(),
          TextButton(
            onPressed: onLogout,
            child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 클래스 내부로 이동된 _menu 함수
  Widget _menu(BuildContext context, IconData icon, String title, bool isEditMenu) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () {
      if (isEditMenu) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileEditScreen(
              loginId: loginId, // 이제 인식됨
              onNicknameChanged: (newNickname) => onLoginSuccess(newNickname, loginId), // 이제 인식됨
            ),
          ),
        );
      }
    },
  );

  // 클래스 내부로 이동된 _buildPointSection 함수
  Widget _buildPointSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('login_id', isEqualTo: loginId) // 클래스 변수 loginId 직접 사용
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(title: Text("포인트 불러오는 중..."));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const ListTile(leading: Icon(Icons.monetization_on, color: Colors.grey), title: Text("내 포인트"), trailing: Text("0 P"));
        }
        final userData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
        final points = userData['point'] ?? 0;
        return ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.deepOrange, 
          child: Text("P",style: TextStyle(color:Colors.white,fontWeight: FontWeight.bold))),
          title: const Text("내 포인트", style: TextStyle(fontWeight: FontWeight.w600)),
          trailing: Text("$points P", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepOrange)),
        );
      },
    );
  }
}
// ---------------------------------------------------------
// 7. 로그인 화면
// ---------------------------------------------------------
class LoginScreen extends StatefulWidget {
  final Function(String, String) onLoginSuccess;
  final VoidCallback? onSignUpTap;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
    this.onSignUpTap,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idController = TextEditingController();
  final _pwController = TextEditingController();
  final CollectionReference _usersCollection = FirebaseFirestore.instance
      .collection('users');
  String _idErrorMessage = '';
  String _pwErrorMessage = '';

  void _login() async {
    final id = _idController.text.trim();
    final pw = _pwController.text.trim();
    setState(() {
      _idErrorMessage = '';
      _pwErrorMessage = '';
    });
    if (id.isEmpty) {
      setState(() => _idErrorMessage = '아이디를 입력해주세요.');
      return;
    }
    if (pw.isEmpty) {
      setState(() => _pwErrorMessage = '비밀번호를 입력해주세요.');
      return;
    }
    try {
      final snapshot = await _usersCollection
          .where('login_id', isEqualTo: id)
          .get();
      if (snapshot.docs.isEmpty) {
        setState(() => _idErrorMessage = '존재하지 않는 아이디입니다.');
        return;
      }
      final userDoc = snapshot.docs.first;
      final dbPassword = userDoc['password'];
      if (dbPassword == pw) {
        final nickname = userDoc['nickname'];
        widget.onLoginSuccess(nickname, id);
        _showSnackBar('$nickname님, 환영합니다! 🎉', Colors.green);
      } else {
        setState(() => _pwErrorMessage = '비밀번호가 일치하지 않습니다.');
      }
    } catch (e) {
      _showSnackBar('로그인 중 오류 발생: $e', Colors.red);
    }
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
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 40,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    '로그인',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 60),
                TextField(
                  controller: _idController,
                  decoration: const InputDecoration(labelText: '아이디'),
                  onChanged: (t) {
                    if (_idErrorMessage.isNotEmpty)
                      setState(() => _idErrorMessage = '');
                  },
                ),
                if (_idErrorMessage.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    _idErrorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 15),
                TextField(
                  controller: _pwController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '비밀번호'),
                  onChanged: (t) {
                    if (_pwErrorMessage.isNotEmpty)
                      setState(() => _pwErrorMessage = '');
                  },
                ),
                if (_pwErrorMessage.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    _pwErrorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                    ),
                    child: const Text(
                      '로그인',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () {
                      if (widget.onSignUpTap != null) {
                        widget.onSignUpTap!();
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                SignUpScreen(onSuccess: widget.onLoginSuccess),
                          ),
                        );
                      }
                    },
                    child: const Text(
                      '아직 회원이 아니신가요? 회원가입',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 8. 회원가입 화면
// ---------------------------------------------------------
class SignUpScreen extends StatefulWidget {
  final Function(String, String) onSuccess;
  const SignUpScreen({super.key, required this.onSuccess});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();
  final TextEditingController _pwConfirmController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsCodeController = TextEditingController();
  final CollectionReference _usersCollection = FirebaseFirestore.instance
      .collection('users');

  bool _isIdChecked = false;
  bool _isNicknameChecked = false;
  bool _isEmailChecked = false;
  bool _isPhoneVerified = false;
  bool _isSmsSent = false;
  bool _isSaving = false;
  String _pwMatchMessage = '';
  String _verificationId = '';
  String _idMessage = '';
  String _nicknameMessage = '';
  String _emailMessage = '';
  String _phoneMessage = '';
  Color _idMsgColor = Colors.red;
  Color _nicknameMsgColor = Colors.red;
  Color _emailMsgColor = Colors.red;
  Color _phoneMsgColor = Colors.red;
  Color _pwMatchMsgColor = Colors.red;

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _checkDuplicateId() async {
    final id = _idController.text.trim();
    if (id.isEmpty) {
      setState(() {
        _idMessage = '아이디를 입력해주세요.';
        _idMsgColor = Colors.red;
        _isIdChecked = false;
      });
      return;
    }
    try {
      final snapshot = await _usersCollection
          .where('login_id', isEqualTo: id)
          .get();
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _idMessage = '이미 사용 중인 아이디입니다.';
          _idMsgColor = Colors.red;
          _isIdChecked = false;
        });
      } else {
        setState(() {
          _idMessage = '사용 가능한 아이디입니다.';
          _idMsgColor = Colors.green;
          _isIdChecked = true;
        });
      }
    } catch (e) {
      _showSnackBar('오류가 발생했습니다: $e', Colors.red);
    }
  }

  Future<void> _checkDuplicateNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() {
        _nicknameMessage = '닉네임을 입력해주세요.';
        _nicknameMsgColor = Colors.red;
        _isNicknameChecked = false;
      });
      return;
    }
    try {
      final snapshot = await _usersCollection
          .where('nickname', isEqualTo: nickname)
          .get();
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _nicknameMessage = '이미 사용 중인 닉네임입니다.';
          _nicknameMsgColor = Colors.red;
          _isNicknameChecked = false;
        });
      } else {
        setState(() {
          _nicknameMessage = '사용 가능한 닉네임입니다.';
          _nicknameMsgColor = Colors.green;
          _isNicknameChecked = true;
        });
      }
    } catch (e) {
      _showSnackBar('오류가 발생했습니다: $e', Colors.red);
    }
  }

  Future<void> _checkDuplicateEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _emailMessage = '이메일을 입력해주세요.';
        _emailMsgColor = Colors.red;
        _isEmailChecked = false;
      });
      return;
    }
    try {
      final snapshot = await _usersCollection
          .where('email', isEqualTo: email)
          .get();
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _emailMessage = '이미 사용 중인 이메일입니다.';
          _emailMsgColor = Colors.red;
          _isEmailChecked = false;
        });
      } else {
        setState(() {
          _emailMessage = '사용 가능한 이메일입니다.';
          _emailMsgColor = Colors.green;
          _isEmailChecked = true;
        });
      }
    } catch (e) {
      _showSnackBar('오류가 발생했습니다: $e', Colors.red);
    }
  }

  void _checkPasswordMatch() {
    final pw = _pwController.text;
    final pwConfirm = _pwConfirmController.text;
    if (pw.isEmpty || pwConfirm.isEmpty) {
      setState(() => _pwMatchMessage = '');
      return;
    }
    if (pw == pwConfirm) {
      setState(() {
        _pwMatchMessage = '비밀번호가 일치합니다.';
        _pwMatchMsgColor = Colors.green;
      });
    } else {
      setState(() {
        _pwMatchMessage = '비밀번호가 일치하지 않습니다.';
        _pwMatchMsgColor = Colors.red;
      });
    }
  }

  Future<void> _sendSmsCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _phoneMessage = '휴대폰 번호를 입력해주세요.';
        _phoneMsgColor = Colors.red;
      });
      return;
    }
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+82${phone.substring(1)}',
      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() {
          _phoneMessage = '발송 실패: ${e.message}';
          _phoneMsgColor = Colors.red;
        });
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
          _isSmsSent = true;
          _phoneMessage = '인증번호가 발송되었습니다.';
          _phoneMsgColor = Colors.blue;
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _verifySmsCode() async {
    final code = _smsCodeController.text.trim();
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: code,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      setState(() {
        _phoneMessage = '휴대폰 인증이 완료되었습니다.';
        _phoneMsgColor = Colors.green;
        _isPhoneVerified = true;
      });
    } catch (e) {
      setState(() {
        _phoneMessage = '인증번호가 일치하지 않습니다.';
        _phoneMsgColor = Colors.red;
        _isPhoneVerified = false;
      });
    }
  }

  Future<void> _saveUserToFirestore() async {
    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await _usersCollection.doc(uid).set({
        'login_id': _idController.text.trim(),
        'password': _pwController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'point': 0,
        'coupons': [],
        'user_status': 'active',
        'created_at': FieldValue.serverTimestamp(),
      });

    } catch (e) {
      _showSnackBar(
        '파이어베이스 저장 오류: $e',
        Colors.red,
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _submitSignUp() async {
    if (!_isIdChecked) {
      setState(() {
        _idMessage = '아이디 중복확인을 완료해주세요.';
        _idMsgColor = Colors.red;
      });
      return;
    }
    if (!_isNicknameChecked) {
      setState(() {
        _nicknameMessage = '닉네임 중복확인을 완료해주세요.';
        _nicknameMsgColor = Colors.red;
      });
      return;
    }
    if (!_isEmailChecked) {
      setState(() {
        _emailMessage = '이메일 중복확인을 완료해주세요.';
        _emailMsgColor = Colors.red;
      });
      return;
    }
    if (!_isPhoneVerified) {
      setState(() {
        _phoneMessage = '휴대폰 인증을 완료해주세요.';
        _phoneMsgColor = Colors.red;
      });
      return;
    }
    if (_pwController.text != _pwConfirmController.text) {
      _showSnackBar('비밀번호가 일치하지 않습니다.', Colors.red);
      return;
    }
    if (_formKey.currentState!.validate()) {
      await _saveUserToFirestore();
      if (!mounted) return;
      widget.onSuccess(
        _nicknameController.text.trim(),
        _idController.text.trim(),
      );
      Navigator.pop(context);
      _showSnackBar('회원가입을 축하합니다! 🎉', Colors.green);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _idController,
                      decoration: const InputDecoration(labelText: '아이디'),
                      onChanged: (v) => setState(() => _isIdChecked = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _checkDuplicateId,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                    ),
                    child: const Text(
                      '중복확인',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              Text(
                _idMessage,
                style: TextStyle(color: _idMsgColor, fontSize: 12),
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _pwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '비밀번호'),
                onChanged: (t) => _checkPasswordMatch(),
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _pwConfirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '비밀번호 확인'),
                onChanged: (t) => _checkPasswordMatch(),
              ),
              if (_pwMatchMessage.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  _pwMatchMessage,
                  style: TextStyle(color: _pwMatchMsgColor, fontSize: 12),
                ),
              ],
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nicknameController,
                      decoration: const InputDecoration(labelText: '닉네임'),
                      onChanged: (v) =>
                          setState(() => _isNicknameChecked = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _checkDuplicateNickname,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                    ),
                    child: const Text(
                      '중복확인',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              Text(
                _nicknameMessage,
                style: TextStyle(color: _nicknameMsgColor, fontSize: 12),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: '이메일'),
                      onChanged: (v) => setState(() => _isEmailChecked = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _checkDuplicateEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                    ),
                    child: const Text(
                      '중복확인',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              Text(
                _emailMessage,
                style: TextStyle(color: _emailMsgColor, fontSize: 12),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      enabled: !_isPhoneVerified,
                      decoration: const InputDecoration(
                        labelText: '휴대폰 번호',
                        hintText: '하이픈(-) 없이 숫자만 입력',
                        hintStyle: TextStyle(fontSize: 14),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? '휴대폰 번호를 입력해주세요.' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _sendSmsCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                    ),
                    child: const Text(
                      '인증번호 발송',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              if (_isSmsSent) ...[
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _smsCodeController,
                        decoration: const InputDecoration(hintText: '인증번호 입력'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _verifySmsCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                      ),
                      child: const Text(
                        '번호 확인',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
              Text(
                _phoneMessage,
                style: TextStyle(color: _phoneMsgColor, fontSize: 12),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submitSignUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        )
                      : const Text(
                          '회원가입 완료',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
    _idController.dispose();
    _pwController.dispose();
    _pwConfirmController.dispose();
    _nicknameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------
// 관리자 화면
// ---------------------------------------------------------
class AdminUserListScreen extends StatefulWidget {
  const AdminUserListScreen({super.key});
  @override
  State<AdminUserListScreen> createState() => _AdminUserListScreenState();
}

class _AdminUserListScreenState extends State<AdminUserListScreen> {
  final CollectionReference<Map<String, dynamic>> _usersRef = FirebaseFirestore
      .instance
      .collection('users');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '관리자 - 회원 목록 조회',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.deepOrange,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _usersRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Center(child: Text('회원 데이터를 로드하는 중 오류가 발생했습니다.'));
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          final userDocs = snapshot.data?.docs ?? [];
          if (userDocs.isEmpty)
            return const Center(
              child: Text(
                '가입된 회원이 없습니다.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: userDocs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final userData = userDocs[index].data();
              final userId = userDocs[index].id;
              final userName =
                  userData['nickname'] ??
                  userData['login_id'] ??
                  userData['userName'] ??
                  '이름 없음';
              final userRole = userData['role'] ?? 'user';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: userRole == 'admin'
                      ? Colors.red.shade100
                      : Colors.grey.shade200,
                  child: Icon(
                    Icons.person,
                    color: userRole == 'admin'
                        ? Colors.red
                        : Colors.grey.shade700,
                  ),
                ),
                title: Text(
                  userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text('ID: $userId | 권한: $userRole'),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminUserDetailScreen(
                      userId: userId,
                      userData: userData,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminUserDetailScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData;

  const AdminUserDetailScreen({
    super.key,
    required this.userId,
    required this.userData,
  });

  @override
  State<AdminUserDetailScreen> createState() =>
      _AdminUserDetailScreenState(userId,userData);
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {

  final String userId;
  final Map<String, dynamic> userData;
   _AdminUserDetailScreenState(this.userId, this.userData);

  final TextEditingController _reasonController =
      TextEditingController();
      
  final TextEditingController _durationController =
    TextEditingController();


  Future<void> _suspendUser() async {

    final int days =
        int.tryParse(_durationController.text.trim()) ?? 0;


    DateTime? suspendedUntil;


    if (days > 0) {
      suspendedUntil =
          DateTime.now().add(
            Duration(days: days),
          );
    }


    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .update({

      'user_status': 'suspended',

      'suspensionReason':
          _reasonController.text.trim(),

      'suspendedAt':
          FieldValue.serverTimestamp(),

      'suspendedUntil':
          suspendedUntil == null
          ? null
          : Timestamp.fromDate(suspendedUntil),

    });


    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('회원이 정지되었습니다.')
      ),
    );

  }



  Future<void> _releaseUser() async {

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .update({

      'user_status': 'active',
      'suspensionReason': '',
      'suspendedAt': null,
      'suspendedUntil': null,

    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('회원 정지가 해제되었습니다.')
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = userData['nickname'] ?? '정보 없음';
    final loginIdField = userData['login_id'] ?? '정보 없음';
    final role = userData['role'] ?? 'user';
    final status = userData['user_status'] ?? 'active';
    final email = userData['email'] ?? '정보 없음';
    final createdAt = userData['createdAt'] is Timestamp
        ? (userData['createdAt'] as Timestamp).toDate().toString()
        : userData['createdAt']?.toString() ?? '정보 없음';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$name 님의 상세 정보',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.deepOrange,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '기본 가입 정보',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(height: 15),
            _buildInfoRow('파이어베이스 문서 ID', userId),
            _buildInfoRow('로그인 ID', loginIdField),
            _buildInfoRow('닉네임 (이름)', name),
            _buildInfoRow('이메일 주소', email),
            _buildInfoRow('계정 권한', role),
            _buildInfoRow('계정 상태', status),
            _buildInfoRow('가입 일시', createdAt),
            const SizedBox(height: 30),
            const Text(
              '회원 관리',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: '정지 사유',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '정지 기간 (일)',
                hintText: '0 입력 시 영구 정지',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [

                Expanded(
                  child: ElevatedButton(
                    onPressed: _suspendUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text(
                      '회원 정지',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: ElevatedButton(
                    onPressed: _releaseUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text(
                      '정지 해제',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),

              ],
            ),
            const SizedBox(height:30),
            const SizedBox(height: 10),
            Card(
              color: Colors.grey.shade50,
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Padding(
                padding: EdgeInsets.all(15),
                child: Text(
                  '이 유저가 작성한 레시피 및 요리 후기 목록은 해당 컬렉션(recipe_list 등)에서 ownerId 필드가 이 유저의 ID와 일치하는 문서를 쿼리하여 추가로 연동할 수 있습니다.',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  @override
  void dispose() {
    _reasonController.dispose();
    _durationController.dispose();
    super.dispose();
  }
}


  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

Future<void> updatePoint(String loginId, int amount) async {
  // 1. login_id로 해당 유저의 문서 찾기
  final userQuery = await FirebaseFirestore.instance
      .collection('users')
      .where('login_id', isEqualTo: loginId)
      .get();

  if (userQuery.docs.isNotEmpty) {
    final userDoc = userQuery.docs.first;
    final currentPoint = userDoc.data()['point'] ?? 0;
    
    // 2. 현재 포인트에 더하기
    await userDoc.reference.update({
      'point': currentPoint + amount,
    });
  }
}
Future<void> earnPoints(String loginId, int points) async {
  try {
    // 1. login_id가 일치하는 문서 찾기
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('login_id', isEqualTo: loginId)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      // 2. 찾은 문서의 ID로 직접 업데이트
      await querySnapshot.docs.first.reference.update({
        'point': FieldValue.increment(points),
      });
    }
  } catch (e) {
    print("포인트 적립 실패: $e");
  }
}
