import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/face_providers.dart';

/// A slim progress banner shown at the top of the People screen while
/// face detection is running.
class FaceAnalysisBanner extends ConsumerWidget {
  const FaceAnalysisBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (processed, total, facesFound) = ref.watch(
      faceAnalysisProgressProvider,
    );

    final progress = total > 0 ? processed / total : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress > 0 ? progress : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detecting faces…',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                if (total > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$processed / $total photos · $facesFound faces found',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
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
