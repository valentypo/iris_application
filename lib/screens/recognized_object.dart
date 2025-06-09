import 'package:flutter/material.dart';

class DetectedObject {
  final Rect boundingBox;
  final String label;
  final double confidence;

  DetectedObject({
    required this.boundingBox,
    required this.label,
    required this.confidence,
  });
}

class ObjectDetailsPage extends StatelessWidget {
  final DetectedObject object;

  const ObjectDetailsPage({super.key, required this.object});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(object.label),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Object: ${object.label}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Confidence: ${(object.confidence * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Location: ${object.boundingBox.toString()}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
