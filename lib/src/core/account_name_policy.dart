import 'package:characters/characters.dart';

const kAccountNameMinCharacters = 1;
const kAccountNameMaxCharacters = 20;
const kAccountNameLengthMessage = 'Use up to 20 characters.';

String normalizeAccountName(String name) => name.trim();

int accountNameCharacterLength(String name) =>
    normalizeAccountName(name).characters.length;

bool isAccountNameLengthValid(String name) {
  final length = accountNameCharacterLength(name);
  return length >= kAccountNameMinCharacters &&
      length <= kAccountNameMaxCharacters;
}

void validateAccountName(String name) {
  if (!isAccountNameLengthValid(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'Use 1-20 user-perceived characters.',
    );
  }
}
