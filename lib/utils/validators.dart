import '../constants/app_constants.dart';

/// Centralized validation utilities
class Validators {
  /// Validate card name
  static String? validateCardName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Nome obbligatorio';
    }
    if (value.trim().length < ValidationConstants.minNameLength) {
      return 'Nome troppo corto';
    }
    if (value.length > ValidationConstants.maxNameLength) {
      return 'Nome troppo lungo (max ${ValidationConstants.maxNameLength} caratteri)';
    }
    return null;
  }

  /// Validate description
  static String? validateDescription(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Descrizione obbligatoria';
    }
    if (value.trim().length < ValidationConstants.minDescriptionLength) {
      return 'Descrizione troppo corta';
    }
    if (value.length > ValidationConstants.maxDescriptionLength) {
      return 'Descrizione troppo lunga (max ${ValidationConstants.maxDescriptionLength} caratteri)';
    }
    return null;
  }

  /// Validate optional text field
  static String? validateOptionalText(String? value, {int? maxLength}) {
    if (value == null || value.trim().isEmpty) {
      return null; // Optional field
    }
    if (maxLength != null && value.length > maxLength) {
      return 'Testo troppo lungo (max $maxLength caratteri)';
    }
    return null;
  }

  /// Validate album capacity
  static String? validateAlbumCapacity(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Capacità obbligatoria';
    }
    final capacity = int.tryParse(value);
    if (capacity == null) {
      return 'Valore non valido';
    }
    if (capacity <= 0) {
      return 'La capacità deve essere maggiore di 0';
    }
    if (capacity > ValidationConstants.maxAlbumCapacity) {
      return 'Capacità massima: ${ValidationConstants.maxAlbumCapacity}';
    }
    return null;
  }

  /// Validate card value/price
  static String? validateCardValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Optional field
    }
    final price = double.tryParse(value);
    if (price == null) {
      return 'Valore non valido';
    }
    if (price < ValidationConstants.minCardValue) {
      return 'Il valore deve essere maggiore o uguale a 0';
    }
    if (price > ValidationConstants.maxCardValue) {
      return 'Valore troppo alto';
    }
    return null;
  }

  /// Validate positive integer
  static String? validatePositiveInt(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Campo obbligatorio' : null;
    }
    final number = int.tryParse(value);
    if (number == null) {
      return 'Valore non valido';
    }
    if (number < 0) {
      return 'Il valore deve essere positivo';
    }
    return null;
  }

  /// Validate email
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email obbligatoria';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Email non valida';
    }
    return null;
  }

  /// Validate password
  static String? validatePassword(String? value, {int minLength = 6}) {
    if (value == null || value.isEmpty) {
      return 'Password obbligatoria';
    }
    if (value.length < minLength) {
      return 'Password troppo corta (minimo $minLength caratteri)';
    }
    return null;
  }

  /// Validate card code (e.g., LOB-001)
  static String? validateCardCode(String? value, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Codice obbligatorio' : null;
    }
    // Basic validation - can be expanded based on specific format requirements
    if (value.length > 50) {
      return 'Codice troppo lungo';
    }
    return null;
  }

  /// Check if a string is a valid catalog
  static bool isValidCatalog(String? catalog) {
    return catalog != null && CatalogConstants.allCatalogs.contains(catalog);
  }

  /// Check if a string is a valid language
  static bool isValidLanguage(String? language) {
    return language != null && LanguageConstants.allLanguages.contains(language);
  }
}

/// Extension methods for validation
extension StringValidation on String? {
  bool get isNullOrEmpty => this == null || this!.trim().isEmpty;
  bool get isNotNullOrEmpty => !isNullOrEmpty;
}
