import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Muestra un banner rojo en la parte superior cuando no hay conexión.
/// Envuelve cualquier widget y no cambia su comportamiento cuando hay red.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with SingleTickerProviderStateMixin {
  bool _offline = false;
  late final StreamSubscription<List<ConnectivityResult>> _sub;
  late final AnimationController _anim;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = CurvedAnimation(parent: _anim, curve: Curves.easeOut);

    _sub = Connectivity().onConnectivityChanged.listen(_onChanged);
    // Chequeo inicial
    Connectivity().checkConnectivity().then((results) => _onChanged(results));
  }

  void _onChanged(List<ConnectivityResult> results) {
    final noRed = results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
    if (noRed == _offline) return;
    setState(() => _offline = noRed);
    if (noRed) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        SizeTransition(
          sizeFactor: _slide,
          axisAlignment: -1,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              color: const Color(0xFFB71C1C),
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 8,
                16,
                10,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Sin conexión a internet',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
