import 'dart:math';

import 'package:flutter/widgets.dart';

import '../create/account_persona_generator.dart';

/// Editable name and picture shared by desktop and mobile account setup.
/// Submission and interrupted-setup protection remain with the owning screen.
class AccountPersonaDraft {
  AccountPersonaDraft({Random? random}) {
    randomise(random: random);
  }

  final nameController = TextEditingController();
  late String profilePictureId;

  void randomise({Random? random}) {
    final suggestion = generateAccountPersona(random: random);
    // Controller listeners must observe the matching picture with the new name.
    profilePictureId = suggestion.profilePictureId;
    nameController.value = TextEditingValue(
      text: suggestion.name,
      selection: TextSelection.collapsed(offset: suggestion.name.length),
    );
  }

  void dispose() => nameController.dispose();
}
