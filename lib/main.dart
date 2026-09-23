import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MemcPlayerApp());
}

class MemcPlayerApp extends StatelessWidget {
  const MemcPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MEMC Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Color(0x22FFFFFF),
        ),
      ),
      home: const VideoPlayerScreen(),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  bool _showControls = true;
  bool _showSettingsMenu = false;
  bool _isLoadingVideo = false;
  String? _videoTitle;
  Timer? _hideTimer;

  bool _ambientMode = true;
  bool _autoRotate = true;
  bool _memcEnabled = true;
  bool _isLandscape = true;
  int _seekStepSeconds = 10;

  double _volumeLevel = 0.5;
  double _brightnessLevel = 0.5;
  bool _showVolumeHud = false;
  bool _showBrightnessHud = false;
  Timer? _hudTimer;

  String? _activeGestureZone;
  bool _isDraggingSlider = false;
  double _sliderDragValue = 0.0;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);

    _initDeviceSettings();
    _applyOrientationSettings();
    _enableMpvSmoothing();
    _listenToPlayerStreams();
  }

  void _listenToPlayerStreams() {
    _positionSub = _player.stream.position.listen((pos) {
      if (mounted && !_isDraggingSlider) {
        setState(() {
          _position = pos;
        });
      }
    });
    _durationSub = _player.stream.duration.listen((dur) {
      if (mounted) {
        setState(() {
          _duration = dur;
        });
      }
    });
    _playingSub = _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });
  }

  Future<void> _enableMpvSmoothing() async {
    if (_player.platform is NativePlayer) {
      final nativePlayer = _player.platform as NativePlayer;
      await nativePlayer.setProperty('video-sync', 'display-resample');
      await nativePlayer.setProperty('interpolation', 'yes');
      await nativePlayer.setProperty('tscale', 'oversample');
    }
  }

  Future<void> _initDeviceSettings() async {
    try {
      VolumeController.instance.showSystemUI = false;
      _volumeLevel = await VolumeController.instance.getVolume();
      _brightnessLevel = await ScreenBrightness().application;
      await _setMemcMode(_memcEnabled);
    } catch (_) {}
  }

  Future<void> _setMemcMode(bool enabled) async {
    setState(() {
      _memcEnabled = enabled;
    });

    try {
      if (enabled) {
        await FlutterDisplayMode.setHighRefreshRate();
        await _enableMpvSmoothing();
      } else {
        await FlutterDisplayMode.setLowRefreshRate();
      }
    } catch (e) {
      debugPrint('Failed to set refresh rate mode: $e');
    }
  }

  void _applyOrientationSettings() {
    if (_autoRotate) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    setState(() {
      _showSettingsMenu = false;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowCompression: false,
      withData: false,
      withReadStream: false,
    );

    if (result != null && result.files.single.path != null) {
      _loadVideoFile(File(result.files.single.path!));
    }
  }

  Future<void> _loadVideoFile(File file) async {
    setState(() {
      _isLoadingVideo = true;
      _videoTitle = file.path.split('/').last;
    });

    try {
      await _player.open(Media(file.path));

      setState(() {
        _isLoadingVideo = false;
      });

      _startHideTimer();
    } catch (e) {
      setState(() {
        _isLoadingVideo = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load video: $e')),
        );
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_showSettingsMenu && !_isDraggingSlider) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showSettingsMenu = false;
      }
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _seekRelative(int seconds) {
    final newPos = _position + Duration(seconds: seconds);
    _player.seek(
      newPos < Duration.zero
          ? Duration.zero
          : (newPos > _duration ? _duration : newPos),
    );
    _startHideTimer();
  }

  void _showHud(String type) {
    _hudTimer?.cancel();
    setState(() {
      if (type == 'volume') {
        _showVolumeHud = true;
        _showBrightnessHud = false;
      } else {
        _showBrightnessHud = true;
        _showVolumeHud = false;
      }
    });
    _hudTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showVolumeHud = false;
          _showBrightnessHud = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final hasMedia = _player.state.playlist.medias.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          final tapX = details.globalPosition.dx;
          if (tapX < screenWidth * 0.4) {
            _seekRelative(-_seekStepSeconds);
          } else if (tapX > screenWidth * 0.6) {
            _seekRelative(_seekStepSeconds);
          }
        },
        onVerticalDragStart: (details) {
          final x = details.globalPosition.dx;
          if (x < screenWidth * 0.18) {
            _activeGestureZone = 'brightness';
          } else if (x > screenWidth * 0.82) {
            _activeGestureZone = 'volume';
          } else {
            _activeGestureZone = null;
          }
        },
        onVerticalDragUpdate: (details) {
          final delta = details.primaryDelta ?? 0;
          if (_activeGestureZone == 'volume') {
            _volumeLevel = (_volumeLevel - (delta / 300)).clamp(0.0, 1.0);
            VolumeController.instance.setVolume(_volumeLevel);
            _showHud('volume');
          } else if (_activeGestureZone == 'brightness') {
            _brightnessLevel = (_brightnessLevel - (delta / 300)).clamp(0.0, 1.0);
            ScreenBrightness().setApplicationScreenBrightness(_brightnessLevel);
            _showHud('brightness');
          }
        },
        onVerticalDragEnd: (_) {
          _activeGestureZone = null;
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_ambientMode && hasMedia)
              Positioned.fill(
                child: Transform.scale(
                  scale: 1.2,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.08),
                      child: Video(
                        controller: _videoController,
                        controls: NoVideoControls,
                      ),
                    ),
                  ),
                ),
              ),
            Center(
              child: hasMedia
                  ? Video(
                      controller: _videoController,
                      controls: NoVideoControls,
                    )
                  : _buildEmptyState(),
            ),
            if (_isLoadingVideo)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'Loading video details...',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            if (_memcEnabled && hasMedia)
              Positioned(
                top: 20,
                right: 20,
                child: _buildGlassChip(
                  icon: Icons.speed_rounded,
                  label: 'MEMC 120Hz Sync',
                ),
              ),
            if (_showVolumeHud)
              _buildSideHud(Icons.volume_up_rounded, _volumeLevel, Alignment.centerRight),
            if (_showBrightnessHud)
              _buildSideHud(Icons.brightness_6_rounded, _brightnessLevel, Alignment.centerLeft),
            if (_showControls) _buildOneUiControls(),
            if (_showControls && _showSettingsMenu) _buildSettingsMenu(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.video_library_rounded, size: 72, color: Colors.white38),
        const SizedBox(height: 16),
        const Text(
          'MEMC Player',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _pickVideo,
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('Open Video File'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white24,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildSideHud(IconData icon, double value, Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              width: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.white24,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(value * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassChip({required IconData icon, required String label}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.white.withValues(alpha: 0.15),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOneUiControls() {
    final double maxDurationMs = _duration.inMilliseconds.toDouble() > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final double currentPosMs = _position.inMilliseconds.toDouble().clamp(0.0, maxDurationMs);

    return Positioned.fill(
      child: Container(
        color: Colors.black38,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _showSettingsMenu ? Icons.close_rounded : Icons.settings_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _showSettingsMenu = !_showSettingsMenu;
                    });
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _videoTitle ?? 'No Video Selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open_rounded, color: Colors.white),
                  onPressed: _pickVideo,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 42,
                  icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                  onPressed: () => _seekRelative(-_seekStepSeconds),
                ),
                const SizedBox(width: 32),
                GestureDetector(
                  onTap: () {
                    _player.playOrPause();
                    _startHideTimer();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 32),
                IconButton(
                  iconSize: 42,
                  icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                  onPressed: () => _seekRelative(_seekStepSeconds),
                ),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(_position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
                SliderTheme(
                  data: SliderThemeData(
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    trackHeight: 4,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _isDraggingSlider ? _sliderDragValue : currentPosMs,
                    min: 0.0,
                    max: maxDurationMs,
                    onChangeStart: (val) {
                      setState(() {
                        _isDraggingSlider = true;
                        _sliderDragValue = val;
                      });
                    },
                    onChanged: (val) {
                      setState(() {
                        _sliderDragValue = val;
                      });
                    },
                    onChangeEnd: (val) async {
                      await _player.seek(Duration(milliseconds: val.toInt()));
                      setState(() {
                        _isDraggingSlider = false;
                      });
                      _startHideTimer();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsMenu() {
    return Positioned(
      top: 60,
      left: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 260,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 20),
                  title: const Text('Open File', style: TextStyle(color: Colors.white, fontSize: 14)),
                  onTap: _pickVideo,
                ),
                const Divider(color: Colors.white12, height: 1),
                SwitchListTile(
                  dense: true,
                  activeThumbColor: Colors.white,
                  title: const Text('Auto Rotate', style: TextStyle(color: Colors.white, fontSize: 14)),
                  value: _autoRotate,
                  onChanged: (val) {
                    setState(() {
                      _autoRotate = val;
                      _applyOrientationSettings();
                    });
                  },
                ),
                if (!_autoRotate)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.screen_rotation_rounded, color: Colors.white, size: 20),
                    title: Text(
                      _isLandscape ? 'Mode: Landscape' : 'Mode: Portrait',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    onTap: () {
                      setState(() {
                        _isLandscape = !_isLandscape;
                        _applyOrientationSettings();
                      });
                    },
                  ),
                SwitchListTile(
                  dense: true,
                  activeThumbColor: Colors.white,
                  title: const Text('Ambient Glow', style: TextStyle(color: Colors.white, fontSize: 14)),
                  value: _ambientMode,
                  onChanged: (val) {
                    setState(() {
                      _ambientMode = val;
                    });
                  },
                ),
                SwitchListTile(
                  dense: true,
                  activeThumbColor: Colors.white,
                  title: const Text('MEMC Smoothing', style: TextStyle(color: Colors.white, fontSize: 14)),
                  value: _memcEnabled,
                  onChanged: (val) {
                    _setMemcMode(val);
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Double Tap Seek', style: TextStyle(color: Colors.white, fontSize: 13)),
                      DropdownButton<int>(
                        value: _seekStepSeconds,
                        dropdownColor: Colors.black87,
                        underline: const SizedBox(),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('5s')),
                          DropdownMenuItem(value: 10, child: Text('10s')),
                          DropdownMenuItem(value: 15, child: Text('15s')),
                          DropdownMenuItem(value: 30, child: Text('30s')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _seekStepSeconds = val;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return hours > 0
        ? '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}'
        : '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}
