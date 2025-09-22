import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DodgerApp());
}

class DodgerApp extends StatelessWidget {
  const DodgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Square Dodger',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  late Ticker _ticker;
  final Random _rng = Random();

  // Game state
  bool _running = false;
  bool _gameOver = false;
  double _elapsed = 0; // seconds
  int _score = 0;
  int _best = 0;

  // World
  Size _worldSize = Size.zero;

  // Player
  final double _playerWidth = 52;
  final double _playerHeight = 18;
  double _playerX = 0; // center x
  double _playerY = 0; // top y (fixed near bottom)
  double _moveTargetX = 0; // where to ease toward (dragging)

  // Obstacles
  final List<_Obstacle> _obs = [];
  double _spawnTimer = 0; // seconds

  Duration? _lastTick;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _running = false;
      _gameOver = false;
      _elapsed = 0;
      _score = 0;
      _obs.clear();
      _spawnTimer = 0;
      _playerX = _worldSize.width / 2;
      _moveTargetX = _playerX;
      _lastTick = null;
    });
  }

  void _start() {
    setState(() {
      _running = true;
      _gameOver = false;
      _elapsed = 0;
      _score = 0;
      _obs.clear();
      _spawnTimer = 0;
      _playerX = _worldSize.width / 2;
      _moveTargetX = _playerX;
      _lastTick = null;
    });
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == null) {
      _lastTick = elapsed;
      return;
    }
    final dtSeconds = (elapsed - _lastTick!).inMicroseconds / 1e6;
    _lastTick = elapsed;

    if (!_running) return;
    _elapsed += dtSeconds;

    // Difficulty curve: increases with time
    final double fallSpeed = 140 + _elapsed * 12; // px/s
    final double spawnInterval = max(0.25, 0.9 - _elapsed * 0.02); // s

    // Move player toward target smoothly
    final double ease = pow(0.001, dtSeconds).toDouble();
    _playerX = _moveTargetX + (_playerX - _moveTargetX) * ease;

    // Clamp player within screen
    final leftBound = _playerWidth / 2;
    final rightBound = _worldSize.width - _playerWidth / 2;
    _playerX = _playerX.clamp(leftBound, rightBound);

    // Spawn
    _spawnTimer += dtSeconds;
    if (_spawnTimer >= spawnInterval) {
      _spawnTimer = 0;
      final w = 24 + _rng.nextDouble() * 44; // 24..68
      final x = w / 2 + _rng.nextDouble() * (_worldSize.width - w);
      _obs.add(_Obstacle(x: x, y: -20, size: w));
    }

    // Update obstacles
    for (final o in _obs) {
      o.y += fallSpeed * dtSeconds;
    }
    _obs.removeWhere((o) => o.y - o.size > _worldSize.height + 40);

    // Collision
    final playerRect = Rect.fromCenter(
      center: Offset(_playerX, _playerY + _playerHeight / 2),
      width: _playerWidth,
      height: _playerHeight,
    );
    for (final o in _obs) {
      final r = Rect.fromCenter(center: Offset(o.x, o.y), width: o.size, height: o.size);
      if (r.overlaps(playerRect)) {
        _running = false;
        _gameOver = true;
        _best = max(_best, _score);
        break;
      }
    }

    // Score
    _score += (100 * dtSeconds).floor();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _worldSize = Size(constraints.maxWidth, constraints.maxHeight);
      _playerY = _worldSize.height - 96;

      final playerRect = Rect.fromCenter(
        center: Offset(_playerX == 0 ? _worldSize.width / 2 : _playerX, _playerY + _playerHeight / 2),
        width: _playerWidth,
        height: _playerHeight,
      );

      return Scaffold(
        backgroundColor: const Color(0xFF87CEEB), // gökyüzü rengi
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => _moveTargetX = d.localPosition.dx,
            onPanUpdate: (d) => _moveTargetX = d.localPosition.dx,
            onTapUp: (d) => _moveTargetX = d.localPosition.dx,
            child: Stack(
              children: [
                // Game canvas
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GamePainter(
                      worldSize: _worldSize,
                      obstacles: _obs,
                      playerRect: playerRect,
                      gameOver: _gameOver,
                      elapsed: _elapsed,
                    ),
                  ),
                ),

                // HUD
                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Badge(text: 'Score: $_score'),
                      _Badge(text: 'Best: $_best'),
                    ],
                  ),
                ),

                // Center overlays
                if (!_running && !_gameOver)
                  _CenterOverlay(
                    child: _Menu(
                      onStart: _start,
                    ),
                  ),
                if (_gameOver)
                  _CenterOverlay(
                    child: _GameOver(score: _score, best: _best, onRestart: _reset, onPlayAgain: _start),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _Obstacle {
  _Obstacle({required this.x, required this.y, required this.size});
  double x;
  double y;
  double size; // square
}

class _GamePainter extends CustomPainter {
  _GamePainter({required this.worldSize, required this.obstacles, required this.playerRect, required this.gameOver, required this.elapsed});

  final Size worldSize;
  final List<_Obstacle> obstacles;
  final Rect playerRect;
  final bool gameOver;
  final double elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Gökyüzü arka planı
    final bg = Rect.fromLTWH(0, 0, size.width, size.height);
    final skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.lightBlue.shade200, Colors.blue.shade700],
    );
    canvas.drawRect(bg, Paint()..shader = skyGradient.createShader(bg));

    // Bulutlar
    final cloudPaint = Paint()..color = Colors.white.withOpacity(0.9);
    for (int i = 0; i < 6; i++) {
      final x = (i * 120 + (elapsed * 30) % size.width) % size.width;
      final y = 60.0 + (i % 3) * 80;
      _drawCloud(canvas, Offset(x, y), cloudPaint);
    }

    // Obstacles
    for (final o in obstacles) {
      paint
        ..color = const Color(0xFF64B5F6)
        ..style = PaintingStyle.fill;
      final r = Rect.fromCenter(center: Offset(o.x, o.y), width: o.size, height: o.size);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
      canvas.drawRRect(rr, paint);

      // Rim light
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xAAFFFFFF),
      );
    }

    // Player
    final player = RRect.fromRectAndRadius(playerRect, const Radius.circular(6));
    canvas.drawRRect(player, Paint()..color = const Color(0xFFFFD54F));
    canvas.drawRRect(player, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xAAFFFFFF));

    if (gameOver) {
      // kırmızı flash overlay
      canvas.drawRect(
        bg,
        Paint()
          ..color = const Color(0x44FF5252)
          ..blendMode = BlendMode.srcOver,
      );
    }
  }

  void _drawCloud(Canvas canvas, Offset center, Paint paint) {
    final r = 20.0;
    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center + const Offset(25, 5), r * 0.9, paint);
    canvas.drawCircle(center + const Offset(-25, 5), r * 0.8, paint);
    canvas.drawCircle(center + const Offset(10, -15), r * 0.7, paint);
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) {
    return oldDelegate.obstacles != obstacles ||
        oldDelegate.playerRect != playerRect ||
        oldDelegate.gameOver != gameOver ||
        oldDelegate.elapsed != elapsed ||
        oldDelegate.worldSize != worldSize;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontFeatures: [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CenterOverlay extends StatelessWidget {
  const _CenterOverlay({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Square Dodger',
          style: TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Parmağı sürükleyerek sarı bloğu hareket ettir.\nMavi karelerden kaç!\nNe kadar uzun yaşarsan o kadar puan.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 24),
        FilledButton.tonal(
          onPressed: onStart,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('BAŞLA'),
          ),
        ),
      ],
    );
  }
}

class _GameOver extends StatelessWidget {
  const _GameOver({required this.score, required this.best, required this.onRestart, required this.onPlayAgain});
  final int score;
  final int best;
  final VoidCallback onRestart;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.white),
        const SizedBox(height: 12),
        const Text(
          'Oyun Bitti',
          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('Skor: $score', style: const TextStyle(color: Colors.white70)),
        Text('En iyi: $best', style: const TextStyle(color: Colors.white38)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.tonal(
              onPressed: onRestart,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('SIFIRLA'),
              ),
            ),
            FilledButton(
              onPressed: onPlayAgain,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('TEKRAR OYNA'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
