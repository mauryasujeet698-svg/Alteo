import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> alteoThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
final ValueNotifier<String> alteoPreferredLanguage = ValueNotifier<String>('English');

Future<void> loadCustomerPreferences() async {
  final store = await SharedPreferences.getInstance();
  final theme = store.getString('alteo_theme') ?? 'light';
  alteoThemeMode.value = switch (theme) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };
  const supported = ['English', 'हिन्दी', 'বাংলা', 'தமிழ்', 'తెలుగు'];
  final language = store.getString('alteo_language') ?? 'English';
  alteoPreferredLanguage.value = supported.contains(language) ? language : 'English';
}

Future<void> setAlteoTheme(ThemeMode mode) async {
  alteoThemeMode.value = mode;
  final value = switch (mode) {
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
    _ => 'light',
  };
  final store = await SharedPreferences.getInstance();
  await store.setString('alteo_theme', value);
}

Future<void> setAlteoLanguage(String language) async {
  const supported = ['English', 'हिन्दी', 'বাংলা', 'தமிழ்', 'తెలుగు'];
  if (!supported.contains(language)) return;
  alteoPreferredLanguage.value = language;
  final store = await SharedPreferences.getInstance();
  await store.setString('alteo_language', language);
}

String alteoText(String key) {
  const translations = <String, Map<String, String>>{
    'हिन्दी': {
      'Home': 'होम', 'Food': 'खाना', 'Ride': 'राइड', 'Profile': 'प्रोफ़ाइल',
      'My orders': 'मेरे ऑर्डर', 'My rides': 'मेरी राइड्स', 'Saved addresses': 'सेव किए गए पते',
      'Payments': 'भुगतान', 'Payment methods': 'भुगतान के तरीके', 'Settings': 'सेटिंग्स',
      'Theme': 'थीम', 'Language': 'भाषा', 'Delete account': 'खाता हटाएँ',
      'Privacy policy': 'गोपनीयता नीति', 'About app': 'ऐप के बारे में',
      'Logout': 'लॉग आउट', 'Cancel': 'रद्द करें', 'Confirm logout?': 'लॉग आउट की पुष्टि करें?',
      'Are you sure you want to log out of your Alteo account?': 'क्या आप वाकई अपने Alteo खाते से लॉग आउट करना चाहते हैं?',
      'Confirm deletion?': 'खाता हटाने की पुष्टि करें?', 'Light': 'लाइट', 'Dark': 'डार्क',
      'Follow device': 'डिवाइस सेटिंग के अनुसार',
    },
    'বাংলা': {
      'Home': 'হোম', 'Food': 'খাবার', 'Ride': 'রাইড', 'Profile': 'প্রোফাইল',
      'My orders': 'আমার অর্ডার', 'My rides': 'আমার রাইড', 'Saved addresses': 'সংরক্ষিত ঠিকানা',
      'Payments': 'পেমেন্ট', 'Payment methods': 'পেমেন্ট পদ্ধতি', 'Settings': 'সেটিংস',
      'Theme': 'থিম', 'Language': 'ভাষা', 'Delete account': 'অ্যাকাউন্ট মুছুন',
      'Privacy policy': 'গোপনীয়তা নীতি', 'About app': 'অ্যাপ সম্পর্কে',
      'Logout': 'লগ আউট', 'Cancel': 'বাতিল', 'Confirm logout?': 'লগ আউট নিশ্চিত করবেন?',
      'Light': 'লাইট', 'Dark': 'ডার্ক', 'Follow device': 'ডিভাইসের সেটিং অনুসরণ করুন',
    },
    'தமிழ்': {
      'Home': 'முகப்பு', 'Food': 'உணவு', 'Ride': 'பயணம்', 'Profile': 'சுயவிவரம்',
      'My orders': 'எனது ஆர்டர்கள்', 'My rides': 'எனது பயணங்கள்', 'Saved addresses': 'சேமித்த முகவரிகள்',
      'Payments': 'கட்டணங்கள்', 'Payment methods': 'கட்டண முறைகள்', 'Settings': 'அமைப்புகள்',
      'Theme': 'தீம்', 'Language': 'மொழி', 'Delete account': 'கணக்கை நீக்கு',
      'Privacy policy': 'தனியுரிமைக் கொள்கை', 'About app': 'செயலி பற்றி',
      'Logout': 'வெளியேறு', 'Cancel': 'ரத்து செய்', 'Confirm logout?': 'வெளியேறுவதை உறுதிப்படுத்தவா?',
      'Light': 'ஒளி', 'Dark': 'இருள்', 'Follow device': 'சாதன அமைப்பைப் பின்பற்று',
    },
    'తెలుగు': {
      'Home': 'హోమ్', 'Food': 'ఆహారం', 'Ride': 'రైడ్', 'Profile': 'ప్రొఫైల్',
      'My orders': 'నా ఆర్డర్లు', 'My rides': 'నా రైడ్లు', 'Saved addresses': 'సేవ్ చేసిన చిరునామాలు',
      'Payments': 'చెల్లింపులు', 'Payment methods': 'చెల్లింపు పద్ధతులు', 'Settings': 'సెట్టింగులు',
      'Theme': 'థీమ్', 'Language': 'భాష', 'Delete account': 'ఖాతాను తొలగించండి',
      'Privacy policy': 'గోప్యతా విధానం', 'About app': 'యాప్ గురించి',
      'Logout': 'లాగ్ అవుట్', 'Cancel': 'రద్దు', 'Confirm logout?': 'లాగ్ అవుట్ నిర్ధారించాలా?',
      'Light': 'లైట్', 'Dark': 'డార్క్', 'Follow device': 'పరికర సెట్టింగ్ అనుసరించు',
    },
  };
  return translations[alteoPreferredLanguage.value]?[key] ?? key;
}
