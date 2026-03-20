import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('cacheBox');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
      ],
      child: const SocialApp(),
    ),
  );
}

class SocialApp extends StatelessWidget {
  const SocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mini Social',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return auth.isAuthenticated
              ? const MainScreen()
              : const LoginScreen();
        },
      ),
    );
  }
}

// --- СЕРВІСИ ---
class StorageService {
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }

  static void cacheData(String key, dynamic data) {
    Hive.box('cacheBox').put(key, jsonEncode(data));
  }

  static dynamic getCachedData(String key) {
    final data = Hive.box('cacheBox').get(key);
    return data != null ? jsonDecode(data) : null;
  }
}

class AuthInterceptor extends Interceptor {
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await StorageService.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      StorageService.clearToken();
    }
    super.onError(err, handler);
  }
}

class ApiClient {
  static Dio get client {
    Dio dio = Dio(
      BaseOptions(
        baseUrl: 'https://dummyjson.com',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    dio.interceptors.add(AuthInterceptor());
    return dio;
  }

  static Future<bool> isOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return true;
    }
  }
}

// --- ПРОВАЙДЕРИ ---
class AuthProvider extends ChangeNotifier {
  bool isAuthenticated = false;
  bool isLoading = false;
  String? username;
  String? avatarUrl;

  AuthProvider() {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await StorageService.getToken();
    if (token != null) {
      isAuthenticated = true;
      final prefs = await SharedPreferences.getInstance();
      username = prefs.getString('username');
      avatarUrl = prefs.getString('avatar');
      notifyListeners();
    }
  }

  Future<bool> login(String user, String pass) async {
    isLoading = true;
    notifyListeners();
    try {
      final response = await ApiClient.client.post(
        '/auth/login',
        data: {'username': user, 'password': pass, 'expiresInMins': 60},
      );

      if (response.statusCode == 200) {
        await StorageService.saveToken(response.data['accessToken']);
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('username', response.data['firstName']);
        prefs.setString('avatar', response.data['image']);
        username = response.data['firstName'];
        avatarUrl = response.data['image'];
        isAuthenticated = true;
        isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      isLoading = false;
      notifyListeners();
      return false;
    }
    return false;
  }

  void logout() async {
    await StorageService.clearToken();
    isAuthenticated = false;
    notifyListeners();
  }
}

class FeedProvider extends ChangeNotifier {
  List<dynamic> posts = [];
  bool isLoading = false;
  bool isOffline = false;

  Future<void> loadPosts() async {
    isLoading = true;
    notifyListeners();
    bool online = await ApiClient.isOnline();
    if (online) {
      try {
        final response = await ApiClient.client.get('/posts?limit=10');
        posts = response.data['posts'];
        StorageService.cacheData('cached_posts', posts);
        isOffline = false;
      } catch (e) {
        _loadFromCache();
      }
    } else {
      _loadFromCache();
    }
    isLoading = false;
    notifyListeners();
  }

  void _loadFromCache() {
    final cached = StorageService.getCachedData('cached_posts');
    if (cached != null) {
      posts = cached;
      isOffline = true;
    }
  }

  Future<void> createPost(String text) async {
    try {
      final response = await ApiClient.client.post(
        '/posts/add',
        data: {'title': text, 'userId': 5},
      );
      posts.insert(0, response.data);
      notifyListeners();
    } catch (e) {}
  }

  // НОВИЙ МЕТОД: Видалення поста
  Future<void> deletePost(int id, int index) async {
    try {
      await ApiClient.client.delete('/posts/$id');
      posts.removeAt(index);
      notifyListeners();
    } catch (e) {}
  }
}

// --- ІНТЕРФЕЙС ---
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final userCtrl = TextEditingController(text: 'emilys');
    final passCtrl = TextEditingController(text: 'emilyspass');

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              const Icon(
                Icons.rocket_launch,
                size: 80,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 20),
              const Text(
                'Mini Social',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: userCtrl,
                decoration: InputDecoration(
                  labelText: 'Логін',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              auth.isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final success = await auth.login(
                          userCtrl.text,
                          passCtrl.text,
                        );
                        if (!success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Помилка авторизації'),
                            ),
                          );
                        }
                      },
                      child: const Text('Увійти'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FeedProvider>(context, listen: false).loadPosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final feed = Provider.of<FeedProvider>(context);

    final screens = [
      RefreshIndicator(
        onRefresh: feed.loadPosts,
        child: Column(
          children: [
            if (feed.isOffline)
              Container(
                width: double.infinity,
                color: Colors.redAccent,
                padding: const EdgeInsets.all(8),
                child: const Text(
                  'Офлайн режим',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: feed.posts.length,
                itemBuilder: (context, index) {
                  final post = feed.posts[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      // Використовуємо ListTile для зручного додавання кошика
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        post['title'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Text(post['body'] ?? ''),
                      // НОВА КНОПКА: Кошик для видалення
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                        onPressed: () => feed.deletePost(post['id'], index),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (auth.avatarUrl != null)
              CircleAvatar(
                radius: 50,
                backgroundImage: NetworkImage(auth.avatarUrl!),
              ),
            const SizedBox(height: 20),
            Text(
              'Привіт, ${auth.username}!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            ElevatedButton(onPressed: auth.logout, child: const Text('Вийти')),
          ],
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Social App'),
        backgroundColor: Colors.deepPurple.shade50,
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.feed), label: 'Стрічка'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Профіль'),
        ],
      ),
      // КНОПКА ДОДАВАННЯ (закриває вимогу "Create" у CRUD)
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () {
                final ctrl = TextEditingController();
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Новий пост'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(hintText: "Що нового?"),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Скасувати'),
                      ),
                      TextButton(
                        onPressed: () {
                          if (ctrl.text.isNotEmpty) {
                            feed.createPost(ctrl.text);
                            Navigator.pop(ctx);
                          }
                        },
                        child: const Text('Додати'),
                      ),
                    ],
                  ),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
