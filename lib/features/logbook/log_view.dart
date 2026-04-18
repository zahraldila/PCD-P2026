import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:logbook_app_094/features/logbook/log_controller.dart';
import 'package:logbook_app_094/features/logbook/log_editor_page.dart';
import 'package:logbook_app_094/features/logbook/models/log_model.dart';
import 'package:logbook_app_094/features/onboarding/onboarding_view.dart';
import 'package:logbook_app_094/features/vision/vision_view.dart';
import 'package:logbook_app_094/helpers/log_helper.dart';
import 'package:logbook_app_094/services/mongo_service.dart';

class LogView extends StatefulWidget {
  final dynamic currentUser;

  const LogView({super.key, required this.currentUser});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final LogController _controller = LogController();

  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _queryNotifier = ValueNotifier<String>('');

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _isOffline = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final offlineNow = results.contains(ConnectivityResult.none);
      if (mounted) setState(() => _isOffline = offlineNow);
    });

    _controller.startBackgroundSync(widget.currentUser['teamId']);
    Future.microtask(() => _initDatabase());
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _searchController.dispose();
    _queryNotifier.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initDatabase() async {
    if (mounted) setState(() => _isLoading = true);

    const source = "log_view.dart";

    try {
      await LogHelper.writeLog(
        "UI: Memulai inisialisasi database...",
        source: source,
        level: 3,
      );

      await MongoService().connect().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          "Koneksi Cloud Timeout. Periksa sinyal / IP Whitelist (0.0.0.0/0).",
        ),
      );

      await _controller.loadLogs(widget.currentUser['teamId']);

      await LogHelper.writeLog(
        "UI: Data berhasil dimuat ke Notifier.",
        source: source,
        level: 2,
      );
    } on SocketException {
      await LogHelper.writeLog(
        "UI: Error - SocketException (offline)",
        source: source,
        level: 1,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Kamu sedang offline. Cek koneksi internet ya."),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on TimeoutException catch (e) {
      await LogHelper.writeLog(
        "UI: Error - TimeoutException ($e)",
        source: source,
        level: 1,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Koneksi timeout. Coba lagi atau cek jaringan/whitelist."),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      await LogHelper.writeLog(
        "UI: Error - $e",
        source: source,
        level: 1,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Masalah: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshFromCloud() async {
    try {
      await MongoService().connect().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException("timeout"),
      );

      await _controller.loadLogs(widget.currentUser['teamId']);
    } on SocketException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Offline: tidak bisa refresh dari cloud."),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Refresh timeout. Coba lagi."),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal refresh: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 11) return "Selamat Pagi";
    if (hour >= 11 && hour < 15) return "Selamat Siang";
    if (hour >= 15 && hour < 18) return "Selamat Sore";
    return "Selamat Malam";
  }

  String _formatLogTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.inSeconds < 60) return "baru saja";
    if (diff.inMinutes < 60) return "${diff.inMinutes} menit yang lalu";
    if (diff.inHours < 24) return "${diff.inHours} jam yang lalu";
    if (diff.inDays < 7) return "${diff.inDays} hari yang lalu";

    return DateFormat("d MMM yyyy", "id_ID").format(local);
  }

  Color _categoryAccent(String category) {
    switch (category) {
      case "Mechanical":
        return Colors.green;
      case "Electronic":
        return Colors.blue;
      case "Software":
        return Colors.deepPurple;
      case "Pekerjaan":
        return Colors.green;
      case "Urgent":
        return Colors.blue;
      case "Pribadi":
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case "Mechanical":
        return Icons.precision_manufacturing_rounded;
      case "Electronic":
        return Icons.memory_rounded;
      case "Software":
        return Icons.code_rounded;
      case "Pekerjaan":
        return Icons.precision_manufacturing_rounded;
      case "Urgent":
        return Icons.memory_rounded;
      case "Pribadi":
        return Icons.code_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Widget _buildCategoryChip({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.18),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMiniBadge({
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.18),
        ),
      ),
      child: Icon(icon, size: 15, color: color),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        splashRadius: 18,
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: color, size: 20),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildTopActionIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildEmptyState({
    required bool isSearching,
    required bool canCreate,
  }) {
    const bodyColor = Color(0xFF4A5A7A);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.78),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                isSearching ? Icons.search_off_rounded : Icons.auto_stories_rounded,
                size: 58,
                color: bodyColor.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isSearching
                  ? "Tidak ada catatan yang cocok"
                  : "Belum ada aktivitas hari ini",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: bodyColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isSearching
                  ? "Coba gunakan kata kunci lain pada judul atau isi catatan."
                  : "Mulai catat kemajuan proyek Anda agar aktivitas tim lebih rapi dan mudah dipantau.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: bodyColor.withOpacity(0.82),
                height: 1.45,
                fontSize: 14,
              ),
            ),
            if (!isSearching && canCreate) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => _goToEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text("Buat Catatan Pertama"),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmLogout() {
    const titleColor = Color(0xFF1F2A44);
    const bodyColor = Color(0xFF4A5A7A);
    const green1 = Color(0xFFA0D468);
    const green2 = Color(0xFF8CC152);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.98),
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titlePadding: EdgeInsets.zero,
        title: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [green1, green2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.logout_rounded, color: titleColor),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Konfirmasi Logout",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: titleColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        content: Text(
          "Apakah Anda yakin ingin keluar?",
          style: TextStyle(
            color: bodyColor.withOpacity(0.95),
            height: 1.3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const OnboardingView()),
                (route) => false,
              );
            },
            child: const Text(
              "Ya, Keluar",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int realIndex, LogModel log) async {
    const titleColor = Color(0xFF1F2A44);
    const bodyColor = Color(0xFF4A5A7A);
    const green1 = Color(0xFFA0D468);
    const green2 = Color(0xFF8CC152);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.98),
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titlePadding: EdgeInsets.zero,
        title: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [green1, green2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: titleColor),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Hapus Catatan?",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: titleColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        content: Text(
          "Yakin mau hapus catatan \"${log.title}\"?\nTindakan ini tidak bisa dibatalkan.",
          style: TextStyle(color: bodyColor.withOpacity(0.95), height: 1.3),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              try {
                if (mounted) setState(() => _isLoading = true);
                await _controller.removeLog(
                  widget.currentUser['uid'],
                  widget.currentUser['role'],
                  realIndex,
                );
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              "Ya, Hapus",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  void _goToEditor({LogModel? log, int? index}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LogEditorPage(
          log: log,
          index: index,
          controller: _controller,
          currentUser: widget.currentUser,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF6F8FF);
    const green1 = Color(0xFFA0D468);
    const green2 = Color(0xFF8CC152);

    const titleColor = Color(0xFF1F2A44);
    const bodyColor = Color(0xFF4A5A7A);
    const cardWhite = Color(0xFFFFFFFF);

    final greeting = _getGreeting();
    const bool canCreate = true;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        toolbarHeight: 62,
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 12,
        title: const Text(
          "LogBook",
          style: TextStyle(
            color: titleColor,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        actions: [
          _buildTopActionIcon(
            icon: Icons.refresh_rounded,
            color: Colors.green,
            onTap: () => _controller.loadLogs(widget.currentUser['teamId']),
          ),
          _buildTopActionIcon(
            icon: Icons.camera_alt_rounded,
            color: Colors.deepPurple,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const VisionView(),
                ),
              );
            },
          ),
          _buildTopActionIcon(
            icon: Icons.logout_rounded,
            color: Colors.red,
            onTap: _confirmLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              backgroundColor: const Color(0xFFDCE4FF),
              foregroundColor: const Color(0xFF1F2A44),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              onPressed: () => _goToEditor(),
              child: const Icon(Icons.add_rounded, size: 28),
            )
          : null,
      body: SafeArea(
        child: Stack(
          children: [
            ClipPath(
              clipper: _HeaderWaveClipper(),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.28,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [green1, green2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: cardWhite.withOpacity(0.93),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Text(
                      "$greeting, ${widget.currentUser['username']} 👋",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Catatan",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: titleColor,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: cardWhite.withOpacity(0.93),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: "Cari judul atau isi catatan...",
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: ValueListenableBuilder<String>(
                          valueListenable: _queryNotifier,
                          builder: (context, q, _) {
                            if (q.isEmpty) return const SizedBox.shrink();
                            return IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchController.clear();
                                _queryNotifier.value = '';
                              },
                            );
                          },
                        ),
                        filled: true,
                        fillColor: Colors.transparent,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (text) =>
                          _queryNotifier.value = text.trim().toLowerCase(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_isOffline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                        border: Border.all(
                          color: const Color(0xFFE8EDF5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.wifi_off_rounded,
                              color: Color(0xFFF2994A),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  "Mode Offline",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: Color(0xFF1F2A44),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Data mungkin belum yang paling terbaru.",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _queryNotifier,
                      builder: (context, query, _) {
                        return ValueListenableBuilder<List<LogModel>>(
                          valueListenable: _controller.logsNotifier,
                          builder: (context, currentLogs, _) {
                            if (_isLoading) {
                              return const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text("Menghubungkan ke MongoDB Atlas..."),
                                  ],
                                ),
                              );
                            }

                            final visibleLogs = currentLogs.where((log) {
                              final isOwner = log.authorId == widget.currentUser['uid'];
                              return isOwner || log.isPublic == true;
                            }).toList()
                              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                            final filteredLogs = query.isEmpty
                                ? visibleLogs
                                : visibleLogs.where((log) {
                                    final q = query.toLowerCase();
                                    return log.title.toLowerCase().contains(q) ||
                                        log.description.toLowerCase().contains(q);
                                  }).toList();

                            if (filteredLogs.isEmpty) {
                              return _buildEmptyState(
                                isSearching: query.isNotEmpty,
                                canCreate: canCreate,
                              );
                            }

                            return RefreshIndicator(
                              onRefresh: _refreshFromCloud,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: filteredLogs.length,
                                itemBuilder: (context, index) {
                                  final log = filteredLogs[index];
                                  final realIndex = currentLogs.indexOf(log);
                                  final accent = _categoryAccent(log.category);

                                  final bool isOwner =
                                      log.authorId == widget.currentUser['uid'];
                                  final bool canUpdate = isOwner;
                                  final bool canDelete = isOwner;

                                  return Dismissible(
                                    key: ValueKey(
                                      "$realIndex-${log.title}-${log.category}",
                                    ),
                                    direction: canDelete
                                        ? DismissDirection.endToStart
                                        : DismissDirection.none,
                                    background: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      alignment: Alignment.centerRight,
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: const Icon(
                                        Icons.delete_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                    confirmDismiss: (_) async {
                                      if (canDelete) {
                                        await _confirmDelete(realIndex, log);
                                      }
                                      return false;
                                    },
                                    child: Container(
                                      height: 160,
                                      margin: const EdgeInsets.symmetric(vertical: 6),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: cardWhite,
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.06),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Align(
                                            alignment: Alignment.center,
                                            child: Container(
                                              width: 52,
                                              height: 52,
                                              decoration: BoxDecoration(
                                                color: accent.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                              child: Icon(
                                                _categoryIcon(log.category),
                                                color: accent,
                                                size: 26,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  log.title,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w900,
                                                    color: titleColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  log.description,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    height: 1.35,
                                                    color: bodyColor.withOpacity(0.92),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    _buildCategoryChip(
                                                      label: log.category,
                                                      color: accent,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    _buildMiniBadge(
                                                      icon: log.isPublic
                                                          ? Icons.public
                                                          : Icons.lock,
                                                      color: log.isPublic
                                                          ? Colors.blue
                                                          : Colors.grey,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    _buildMiniBadge(
                                                      icon: log.isSynced
                                                          ? Icons.cloud_done
                                                          : Icons.cloud_off,
                                                      color: log.isSynced
                                                          ? Colors.green
                                                          : Colors.orange,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  _formatLogTime(log.createdAt),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (canUpdate)
                                                _buildActionButton(
                                                  icon: Icons.edit_rounded,
                                                  color: Colors.blue,
                                                  onTap: () => _goToEditor(
                                                    log: log,
                                                    index: realIndex,
                                                  ),
                                                ),
                                              if (canUpdate && canDelete)
                                                const SizedBox(height: 8),
                                              if (canDelete)
                                                _buildActionButton(
                                                  icon: Icons.delete_rounded,
                                                  color: Colors.red,
                                                  onTap: () => _confirmDelete(
                                                    realIndex,
                                                    log,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
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

class _HeaderWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 58);

    path.cubicTo(
      size.width * 0.22,
      size.height + 18,
      size.width * 0.65,
      size.height - 120,
      size.width,
      size.height - 58,
    );

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}