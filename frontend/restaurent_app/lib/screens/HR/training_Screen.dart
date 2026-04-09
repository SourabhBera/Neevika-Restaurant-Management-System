import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

class TrainingVideoScreen extends StatelessWidget {
  final List<TrainingVideo> videos = [
    TrainingVideo(
      title: 'Table Service Basics',
      description: 'Captain Do\'s & Dont',
      thumbnailUrl: 'https://img.youtube.com/vi/4rJq7rypSv4/maxresdefault.jpg',
      url: 'https://youtu.be/4rJq7rypSv4?si=6jY63c3dTTTl25Cw',
    ),
    TrainingVideo(
      title: 'How to Carry a Restaurant Serving Tray',
      description: 'Step-by-step guide to Carry a Restaurant Serving Tray.',
      thumbnailUrl: 'https://img.youtube.com/vi/ZY5AdDyYQQA/maxresdefault.jpg',
      url: 'https://youtu.be/ZY5AdDyYQQA?si=29QN_QR5hSELkYqN',
    ),
    TrainingVideo(
      title: 'How To Interact With Guests and Taking orders: A Servers Guide',
      description: 'Overview of interacting with the customer.',
      thumbnailUrl: 'https://img.youtube.com/vi/jVef6YBgPhc/maxresdefault.jpg',
      url: 'https://youtu.be/jVef6YBgPhc?si=qDAD-n0Kt_0lRh4d',
    ),
  ];

  TrainingVideoScreen({super.key});

  Future<void> _launchVideo(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      
      // Try to launch with external application mode first
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        // Fallback to platform default
        await launchUrl(uri);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to open video: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Training Videos',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: videos.length,
        itemBuilder: (context, index) {
          final video = videos[index];

          return GestureDetector(
            onTap: () => _launchVideo(video.url, context),
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail with play button overlay
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                        child: Image.network(
                          video.thumbnailUrl,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 180,
                              color: Colors.grey.shade300,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            height: 180,
                            color: Colors.grey.shade300,
                            child: const Center(
                              child: Icon(Icons.videocam, size: 40),
                            ),
                          ),
                        ),
                      ),
                      // Play button overlay
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Title + Description
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          video.description,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Tap to watch indicator
                        Row(
                          children: [
                            Icon(
                              Icons.touch_app,
                              size: 16,
                              color: Colors.blue.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to watch',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.blue.shade600,
                                fontWeight: FontWeight.w500,
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
        },
      ),
    );
  }
}

class TrainingVideo {
  final String title;
  final String description;
  final String thumbnailUrl;
  final String url;

  TrainingVideo({
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.url,
  });
}