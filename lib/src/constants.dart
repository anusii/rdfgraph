@Deprecated('Should use @base and empty prefix : for different purposes')
enum BaseType { shorthandBase, defaultBase }

extension ParseToString on BaseType {
  String get name => this.toString().split('.').last;
}

/// Keyword for @base
const BASE = 'BASE';

/// Most common namespace addresses including RDF, FOAF, XSD, RDFS, OWL
///
/// Reference:
/// [1]: Reserved Vocabulary of OWL 2 - https://www.w3.org/TR/owl-syntax/#IRIs
/// [2]: Built-in datatypes and definitions (XSD is preferred): https://www.w3.org/TR/xmlschema11-2/#built-in-datatypes
/// [3]: XSD datatypes: https://www.w3.org/2011/rdf-wg/wiki/XSD_Datatypes
const String rdfAnchor = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
const String foafAnchor = 'http://xmlns.com/foaf/0.1/';
const String xsdAnchor = 'http://www.w3.org/2001/XMLSchema#';
const String rdfsAnchor = 'http://www.w3.org/2000/01/rdf-schema#';
const String owlAnchor = 'http://www.w3.org/2002/07/owl#';

/// Language tags
/// Based on ISO 639-1 standard language codes (ref: https://www.andiamo.co.uk/resources/iso-language-codes/)
const langTags = [
  'af',
  'ar-ae',
  'ar-bh',
  'ar-dz',
  'ar-eg',
  'ar-iq',
  'ar-jo',
  'ar-kw',
  'ar-lb',
  'ar-ly',
  'ar-ma',
  'ar-om',
  'ar-qa',
  'ar-sa',
  'ar-sy',
  'ar-tn',
  'ar-ye',
  'be',
  'bg',
  'ca',
  'cs',
  'cy',
  'da',
  'de',
  'de-at',
  'de-ch',
  'de-li',
  'de-lu',
  'el',
  'en',
  'en-au',
  'en-bz',
  'en-ca',
  'en-gb',
  'en-ie',
  'en-jm',
  'en-nz',
  'en-tt',
  'en-us',
  'en-za',
  'es',
  'es-ar',
  'es-bo',
  'es-cl',
  'es-co',
  'es-cr',
  'es-do',
  'es-ec',
  'es-gt',
  'es-hn',
  'es-mx',
  'es-ni',
  'es-pa',
  'es-pe',
  'es-pr',
  'es-py',
  'es-sv',
  'es-uy',
  'es-ve',
  'et',
  'eu',
  'fa',
  'fi',
  'fo',
  'fr',
  'fr-be',
  'fr-ca',
  'fr-ch',
  'fr-lu',
  'ga',
  'gd',
  'he',
  'hi',
  'hr',
  'hu',
  'id',
  'is',
  'it',
  'it-ch',
  'ja',
  'ji',
  'ko',
  'ko',
  'ku',
  'lt',
  'lv',
  'mk',
  'ml',
  'ms',
  'mt',
  'nb',
  'nl',
  'nl-be',
  'nn',
  'no',
  'pa',
  'pl',
  'pt',
  'pt-br',
  'rm',
  'ro',
  'ro-md',
  'ru',
  'ru-md',
  'sb',
  'sk',
  'sl',
  'sq',
  'sr',
  'sv',
  'sv-fi',
  'th',
  'tn',
  'tr',
  'ts',
  'uk',
  'ur',
  've',
  'vi',
  'xh',
  'zh-cn',
  'zh-hk',
  'zh-sg',
  'zh-tw',
  'zu',
];
