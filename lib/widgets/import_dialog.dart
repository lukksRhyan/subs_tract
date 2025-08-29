import 'package:flutter/material.dart';

class ImportDialog extends StatelessWidget{
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Import Subtitles'),
      content: Column(
        children: [
          TextField(
            decoration: InputDecoration(labelText: 'File Path'),
          ),
          TextField(
            decoration: InputDecoration(labelText: 'Language'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Handle import action
          },
          child: Text('Import'),
        ),
      ],
    );
  }
}