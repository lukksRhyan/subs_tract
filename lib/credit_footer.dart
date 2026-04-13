import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class CreditFooter extends StatelessWidget {
  final Uri _url = Uri.parse('https://github.com/lukksRhyan');

  Future<void> _launchUrl() async {
    if (!await launchUrl(_url)) {
      throw Exception('Não foi possível abrir $_url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _launchUrl,
      child: Text(
        'Criado por Lucas Rhyan',
        style: TextStyle(
          fontSize: 16,
          color: Colors.blueAccent,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
