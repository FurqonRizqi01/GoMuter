import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _orange = Color(0xFFF97316);

  static const List<_SlideData> _slides = [
    _SlideData(
      icon: Icons.storefront_rounded,
      title: 'Selamat Datang\ndi GoMuter',
      description:
          'Platform yang menghubungkan kamu dengan Pedagang Kaki Lima '
          'terdekat. Temukan jajanan favoritmu dengan mudah!',
    ),
    _SlideData(
      icon: Icons.location_on_rounded,
      title: 'Temukan PKL\nTerdekat',
      description:
          'Gunakan peta interaktif untuk melihat lokasi PKL di sekitarmu. '
          'Lihat menu, harga, dan jarak secara real-time.',
    ),
    _SlideData(
      icon: Icons.shopping_bag_rounded,
      title: 'Pesan &\nBayar Mudah',
      description:
          'Pre-order makanan dari PKL favoritmu dan ambil tanpa antre. '
          'Praktis, cepat, dan hemat waktu!',
    ),
  ];

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onFinished();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 16),
                child: TextButton(
                  onPressed: widget.onFinished,
                  child: const Text(
                    'Lewati',
                    style: TextStyle(
                      color: _orange,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),

            // Page slides
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) =>
                    _SlidePage(data: _slides[index]),
              ),
            ),

            // Dot indicator
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == i ? 28 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? _orange
                          : _orange.withAlpha(77),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ),

            // Next / Mulai button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(isLast ? 'Mulai' : 'Lanjut'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Slide data model ──

class _SlideData {
  final IconData icon;
  final String title;
  final String description;

  const _SlideData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

// ── Individual slide widget ──

class _SlidePage extends StatelessWidget {
  final _SlideData data;

  const _SlidePage({required this.data});

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF97316);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon circle
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: orange.withAlpha(26),
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, size: 80, color: orange),
          ),
          const SizedBox(height: 48),

          // Title
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),

          // Description
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
