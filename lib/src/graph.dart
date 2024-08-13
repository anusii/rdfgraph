import 'dart:convert';
import 'dart:io' show File;

import 'package:http/http.dart' as http;
import 'package:universal_io/io.dart' show Platform;

import 'namespace.dart';
import './term.dart';
import 'triple.dart';
import 'constants.dart';
import '../parser/grammar_parser.dart';

class Graph {
  /// The set to store different groups of triples
  @Deprecated('Use [Graph.groups] instead')
  Map<URIRef, Set<Triple>> graphs = {};

  /// The set to store prefixed namespaces
  @Deprecated('Use [Graph.ctx] instead')
  Map<String, String> contexts = {};

  /// The set to store different groups of triples in the form of
  /// {sub1: {pre1: {obj1}, pre2, {obj2, obj2_1}}, sub2: {pre3: {obj3, obj3_1}, ...}, ...}
  // TODO: turtle subject as a BlankNode as subjects can be {iri, BlankNode, collection}, and iri can be {IRIREF, PrefixedName}, the current implementation only deals with iri (implemented as URIRef) as subject.
  Map<URIRef, Map<URIRef, Set>> groups = {};

  /// The set to store all prefixed namespaces.
  Map<String, URIRef> ctx = {};

  /// The set to store all triples in the graph.
  Set triples = {};

  /// The string for storing serialized string after parsing.
  String serializedString = '';

  /// The grammar parser to extract file content to a list.
  final parser = EvaluatorDefinition().build();

  /// Adds a triple to group using its string forms.
  ///
  /// Note:
  /// 1. Because the triple is a set, no duplicates are allowed.
  /// 2. If the added triple contains undefined namespace (except for standard
  /// namespaces such as XSD, OWL, RDF, FOAF, RDFS), it would be ignored.
  /// When using item(), if the namespace is undefined, then it will cause an
  ///  exception and the triple will not be added. To avoid this, first use
  ///  [Graph.addPrefixToCtx] to update the prefixed namespace context, then
  /// use [Graph.addTripleToGroups]
  /// 3. If it's a standard namespace, the context set [ctx] will be updated
  /// automatically by [Graph._updateCtx].
  /// 4. [s], [p], [o] can be valid strings as subject, predicate, ar object,
  /// OR they can use the URIRef or other valid forms (e.g. object can be a
  /// Literal.
  ///
  /// Example:
  /// ```dart
  /// Graph g = Graph();
  ///
  /// final donna = URIRef('http://example.org/donna');
  /// g.addTripleToGroups(donna, RDF.type, FOAF.Person);
  /// g.addTripleToGroups(donna, FOAF.nick, Literal('donna', lang: 'en'));
  /// g.addTripleToGroups(donna, FOAF.name, Literal('Donna Fales'));
  /// g.addTripleToGroups(donna, FOAF.mbox, URIRef('mailto:donna@example.org'));
  ///
  /// for (Triple t in g.triples) {
  ///   print(t);
  /// }
  /// ```
  void addTripleToGroups(dynamic s, dynamic p, dynamic o) {
    // TODO: subject as a BlankNode
    try {
      dynamic sub =
          (s.runtimeType == URIRef || s.runtimeType == BNode) ? s : item(s);
      _updateCtx(sub, ctx);
      if (!groups.containsKey(sub)) {
        groups[sub] = Map();
      }
      dynamic pre = (p.runtimeType == URIRef) ? p : item(p);
      _updateCtx(pre, ctx);
      if (!groups[sub]!.containsKey(pre)) {
        groups[sub]![pre] = Set();
      }
      var obj = (o.runtimeType == String) ? item(o) : o;
      if (obj.runtimeType == URIRef || obj.runtimeType == BNode) {
        _updateCtx(obj, ctx);
      } else if (obj.runtimeType == Literal) {
        Literal objLiteral = obj as Literal;
        if (objLiteral.datatype != null) {
          _updateCtx(objLiteral.datatype!, ctx);
        }
      } else if (obj.runtimeType == String) {
        _updateCtx(XSD.string, ctx);
      }
      // Updates triple sets as well.
      groups[sub]![pre]!.add(obj);
      triples.add(Triple(sub: sub, pre: pre, obj: obj));
    } catch (e) {
      print('Error occurred when adding triple ($s, $p, $o), '
          'groups not updated. Error detail: $e');
    }
  }

  /// Adds a prefix to context using its string forms
  ///
  /// Overwrites the previous prefix name if it already exists in context
  void addPrefixToCtx(String prefixName, URIRef uriRef) {
    // Append ':' in the end for consistency and serialization as all keys in
    // [ctx] ends with ':' (except for 'BASE' key).
    if (!prefixName.endsWith(':')) {
      prefixName += ':';
    }
    ctx[prefixName] = uriRef;
  }

  /// Adds triple to the set, also update the graph to include the triple.
  ///
  /// It uses a triples set can avoid duplicated records.
  @Deprecated(
      'Use [Graph.addTripleToGroups] and [Graph.addPrefixToCtx] instead')
  void add(Triple triple) {
    triples.add(triple);

    // Create a new set if key is not existed (a new triple group identity).
    if (!graphs.containsKey(triple.sub)) {
      graphs[triple.sub] = Set();
    }
    graphs[triple.sub]!.add(triple);

    /// Update the prefixes/contexts by iterating through sub, pre, obj.
    _updateContexts(triple.sub, contexts);
    _updateContexts(triple.pre, contexts);
    if (triple.obj.runtimeType == Literal) {
      Literal objLiteral = triple.obj as Literal;
      if (objLiteral.datatype != null) {
        _updateContexts(objLiteral.datatype!, contexts);
      }
    } else if (triple.obj.runtimeType == URIRef) {
      // Need to update contexts for URIRef objects as well.
      URIRef o = triple.obj as URIRef;
      _updateContexts(o, contexts);
    }
  }

  /// Adds named individual to the graph: <subject> rdf:type owl:NamedIndividual
  @Deprecated('Use [Graph.addNamedIndividualToGroups] instead')
  bool addNamedIndividual(URIRef sub) {
    // Check if the new individual already exists in the graph, and if it's
    // already there, can't add it and return false.
    if (_namedIndividualExists(sub)) {
      return false;
    }
    Triple newNamedIndividual = Triple(
        sub: sub,
        pre: RDF.type,
        // Note that both ways work, but [OWL.NamedIndividual] is more succinct
        // obj: Literal('', datatype: OWL.NamedIndividual));
        obj: OWL.NamedIndividual);
    // Call [add] method to update contexts instead of just adding them to
    // triples.
    add(newNamedIndividual);
    return true;
  }

  /// Adds named individual to graph: <subject> rdf:type owl:NamedIndividual.
  bool addNamedIndividualToGroups(dynamic s) {
    // Check whether the new individual already exists in the graph.
    // If it's already there, can't add it and return false because adding
    // a named individual is usually the first step when we add a new group of
    // triples in the Graph.
    try {
      URIRef sub = (s.runtimeType == URIRef) ? s : item(s) as URIRef;
      if (_namedIndividualExists(sub)) {
        return false;
      }
      // Note [a] is equivalent to RDF.type. By using [Graph.addTripleToGroup],
      // we are updating both the triples and the namespaces as well.
      addTripleToGroups(sub, a, OWL.NamedIndividual);
    } catch (e) {
      print('Error occurred when adding named individual $s. Error detail: $e');
      return false;
    }
    return true;
  }

  /// Adds property to graph: <subject> rdf:type owl:<uriRef.value>.
  bool addPropertyToGroups(dynamic s, dynamic uriRefBase) {
    // Check whether the new uriRef.value already exists in the graph.
    // If it's already there, can't add it and return false because adding
    // a named individual is usually the first step when we add a new group of
    // triples in the Graph.
    try {
      URIRef sub = (s.runtimeType == URIRef) ? s : item(s) as URIRef;
      if (_namedIndividualExists(sub)) {
        return false;
      }
      // Note [a] is equivalent to RDF.type. By using [Graph.addTripleToGroup],
      // we are updating both the triples and the namespaces as well.
      addTripleToGroups(sub, a, URIRef.fullUri(owlAnchor).slash(uriRefBase));
    } catch (e) {
      print('Error occurred when adding named individual $s. Error detail: $e');
      return false;
    }
    return true;
  }

  /// Checks if a named individual already exists in the graph.
  bool _namedIndividualExists(URIRef sub) {
    for (Triple t in triples) {
      if (t.sub == sub) {
        return true;
      }
    }
    return false;
  }

  /// Adds object property to link two triple subjects together.
  ///
  /// Throws an [Exception] if the relationship already exist.
  /// Here the object is different from the object in the triple.
  void addObjectProperty(URIRef obj, URIRef relation, URIRef prop) {
    // Creates the triple to represent the new relationship
    Triple newRelation = Triple(sub: obj, pre: relation, obj: prop);
    if (triples.contains(newRelation)) {
      throw Exception('Triples are already linked!');
    } else {
      addTripleToGroups(obj, relation, prop);
    }
  }

  /// Updates standard prefixes to include in the contexts.
  @Deprecated('Use [Graph._updateCtx] instead')
  void _updateContexts(URIRef u, Map ctx) {
    for (String sp in standardPrefixes.keys) {
      if (u.inNamespace(Namespace(ns: standardPrefixes[sp]!)) &&
          !ctx.containsKey(sp)) {
        ctx[sp] = standardPrefixes[sp];
      }
    }
  }

  /// Updates the context with the new URIRef instance for standard prefixes.
  ///
  /// Note:
  /// It's only useful for adding standard prefixes (see namespaces.dart). Use
  /// [Graph.addPrefixToCtx] for explicit updating [Graph.ctx].
  void _updateCtx(URIRef u, Map ctx) {
    for (String sp in standardPrefixes.keys) {
      if (u.inNamespace(Namespace(ns: standardPrefixes[sp]!)) &&
          !ctx.containsKey('$sp:')) {
        ctx['$sp:'] = URIRef(standardPrefixes[sp]!);
      }
    }
  }

  /// Binds a namespace to a prefix for better readability when serializing.
  ///
  /// Throws an [Exception] if trying to bind the name that already exists.
  /// Example:
  /// ```dart
  /// Graph g = Graph();
  /// g.bind('example', Namespace('http://example.org/');
  /// ```
  void bind(String name, Namespace ns) {
    // For consistency, the key in [Graph.ctx] ends with ':'.
    if (!name.endsWith(':')) {
      name += ':';
    }
    if (!ctx.containsKey(name)) {
      ctx[name] = ns.uriRef!;
    } else {
      throw Exception("$name already exists in prefixed namespaces!");
    }
  }

  /// Finds all subjects which have a certain predicate and object.
  ///
  /// If `pre` is provided, it checks for the predicate.
  /// If `obj` is provided, it checks for the object.
  /// If both are provided, it checks for both predicate and object.
  /// If neither is provided, it returns all subjects in the triples.
  Set<URIRef> subjects({URIRef? pre, dynamic obj}) {
    // Initialize an empty set to store the subjects.
    Set<URIRef> subs = {};

    // Iterate over all triples in the graph.
    for (Triple t in triples) {
      // Check if the pre condition matches, if provided.
      bool preMatches = pre == null || t.pre == pre;
      // Check if the obj condition matches, if provided.
      bool objMatches = obj == null || t.obj == obj;

      // If both conditions match (or are not provided), add the subject.
      if (preMatches && objMatches) {
        subs.add(t.sub);
      }
    }

    // Return the set of subjects.
    return subs;
  }

  /// Finds all objects which have a certain subject and predicate.
  ///
  /// If `sub` is provided, it checks for the subject.
  /// If `pre` is provided, it checks for the predicate.
  /// If both are provided, it checks for both subject and predicate.
  /// If neither is provided, it returns all objects in the triples.
  Set<dynamic> objects({URIRef? sub, URIRef? pre}) {
    // Initialize an empty set to store the objects.
    Set<dynamic> objs = {};

    // Iterate over all triples in the graph.
    for (Triple t in triples) {
      // Check if the sub condition matches, if provided.
      bool subMatches = sub == null || t.sub == sub;
      // Check if the pre condition matches, if provided.
      bool preMatches = pre == null || t.pre == pre;

      // If both conditions match (or are not provided), add the object.
      if (subMatches && preMatches) {
        objs.add(t.obj);
      }
    }

    // Return the set of objects.
    return objs;
  }

  /// Finds all predicates which have a certain subject and object.
  ///
  /// If `sub` is provided, it checks for the subject.
  /// If `obj` is provided, it checks for the object.
  /// If both are provided, it checks for both subject and object.
  /// If neither is provided, it returns all predicates in the triples.
  Set<URIRef> predicates({URIRef? sub, dynamic obj}) {
    // Initialize an empty set to store the predicates.
    Set<URIRef> pres = {};

    // Iterate over all triples in the graph.
    for (Triple t in triples) {
      // Check if the sub condition matches, if provided.
      bool subMatches = sub == null || t.sub == sub;
      // Check if the obj condition matches, if provided.
      bool objMatches = obj == null || t.obj == obj;

      // If both conditions match (or are not provided), add the predicate.
      if (subMatches && objMatches) {
        pres.add(t.pre);
      }
    }

    // Return the set of predicates.
    return pres;
  }

  /// Finds all triples which have a certain value.
  ///
  /// This method checks if the given [value] matches any of the components
  /// (subject, predicate, or object) of the triples in the graph. It returns
  /// a set of triples where any of these components matches the [value].
  ///
  /// Example usage:
  /// ```dart
  /// final value = 'exampleValue';
  /// final matchingTriples = matchTriples(value);
  /// print(matchingTriples);
  /// ```
  Set<Triple> matchTriples(String value) {
    // Initialize an empty set to store the matching triples.
    Set<Triple> matchingTriples = {};

    // Iterate over all triples in the graph.
    for (Triple t in triples) {
      // Check if the subject, predicate, or object matches the given value.
      if (t.sub.value == value ||
          t.pre.value == value ||
          t.obj.toString() == value) {
        // If any component matches, add the triple to the set of matching triples.
        matchingTriples.add(t);
      }
    }

    // Return the set of matching triples.
    return matchingTriples;
  }

  /// Parses file and update graph accordingly.
  @Deprecated('Use [Graph.parseTurtle] instead for parsing a turtle string')
  parse(String filePath) async {
    final file = File(filePath);
    Stream<String> lines =
        file.openRead().transform(utf8.decoder).transform(LineSplitter());
    try {
      Map<String, dynamic> config = {
        'prefix': false,
        'sub': URIRef('http://sub.placeholder.pl'),
        'pre': URIRef('http://pre.placeholder.pl')
      };
      await for (var line in lines) {
        // Remove leading and trailing spaces.
        line = line.trim();
        config = _parseLine(line, config);
      }
    } catch (e) {
      print('Error in parsing: $e');
    }
  }

  /// Parses whole text and update graph accordingly.
  @Deprecated('Use [Graph.parseTurtle] instead for parsing a turtle string')
  parseText(String text) {
    List<String> lines = text.split(Platform.isWindows ? '\r\n' : '\n');
    try {
      Map<String, dynamic> config = {
        'prefix': false,
        'sub': URIRef('http://sub.placeholder.pl'),
        'pre': URIRef('http://pre.placeholder.pl')
      };
      for (var i = 0; i < lines.length; i++) {
        // Removes leading and trailing spaces.
        String line = lines[i].trim();
        config = _parseLine(line, config);
      }
    } catch (e) {
      print('Error in parsing text: $e');
    }
  }

  /// Parse the line and update the graph
  ///
  /// Note:
  /// [config] is used to hold and update prefix, subject and predicate.
  /// It's a Map so we can change its value (not reference) although Dart
  /// param is passed by value (in this case, the address is passed).
  @Deprecated('Should not use this method as it\'s not robust in grammar.'
      'Will remove this method in the future.')
  Map<String, dynamic> _parseLine(String line, Map<String, dynamic> config) {
    URIRef sub = config['sub']! as URIRef;
    URIRef pre = config['pre']! as URIRef;

    /// 1. Parse prefix line to store in map contexts.
    if (line.startsWith('@') && line.endsWith('.')) {
      // Updates contexts first.
      _parsePrefix(line);
      return {'prefix': true, 'sub': sub, 'pre': pre};
    } else {
      // Use regex for parsing space in side quotes: \s(?=(?:[^'"`]*(['"`])[^'"`]*\1)*[^'"`]*$)
      // instead of just using List<String> lst = line.split(' '); which will
      // not work for line like 'foaf:name "Edward Scissorhands"^^xsd:string ;'
      final re = RegExp(r'\s(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)');
      List<String> lst = line.split(re);
      dynamic obj;
      if (line.endsWith(';')) {
        // 2. Parse triple line ending with ';'.
        // Triple line with next line containing two elements of predicate and
        // object depending on how many elements in the line (the last one is
        // ';').
        if (lst.length == 3 + 1) {
          // Full triple line with 3 elements.
          // Sub will be re-used for following lines with 2 or 1 element(s).
          sub = _parseElement(lst[0]) as URIRef;

          // Pre will be re-used for following line with 1 element.
          pre = _parseElement(lst[1]) as URIRef;
          obj = _parseElement(lst[2]);

          // Add to triples set.
          add(Triple(sub: sub, pre: pre, obj: obj));
        } else if (lst.length == 2 + 1) {
          // Sub is omitted with 2 elements in this line.
          pre = _parseElement(lst[0]) as URIRef;
          obj = _parseElement(lst[1]);

          // Re-use last sub.
          add(Triple(sub: sub, pre: pre, obj: obj));
        } else if (lst.length == 1 + 1) {
          // Example:
          // sub pre obj1 ,
          //         obj ;
          obj = _parseElement(lst[0]);
          add(Triple(sub: sub, pre: pre, obj: obj));
        } else {
          throw Exception('Error: illegal line ending with ";" $line');
        }
      } else if (line.endsWith(',')) {
        // 3. Parse triple line ending with ','
        // Triple line with next line containing one element of object.
        if (lst.length == 1 + 1) {
          // Reuse the previous sub and pre.
          obj = _parseElement(lst[0]);
          add(Triple(sub: sub, pre: pre, obj: obj));
        } else if (lst.length == 2 + 1) {
          // Example:
          // sub pre1 obj1 ,
          //         obj ;
          //     pre2 obj2 ,
          //          obj3 ,
          pre = _parseElement(lst[0]) as URIRef;
          obj = _parseElement(lst[1]);
          add(Triple(sub: sub, pre: pre, obj: obj));
        } else if (lst.length == 3 + 1) {
          // Example:
          // sub pre obj1 ,
          //         obj2 ;
          // Sub will be re-used for following lines with 2 or 1 element(s)
          sub = _parseElement(lst[0]) as URIRef;

          // Pre will be re-used for following line with 1 element
          pre = _parseElement(lst[1]) as URIRef;
          obj = _parseElement(lst[2]);
          add(Triple(sub: sub, pre: pre, obj: obj));
        } else {
          throw Exception('Error: illegal line ending with "," $line');
        }
      } else if (line.endsWith('.')) {
        /// 4. Parse triple line ending with '.'
        if (lst.length == 3 + 1) {
          sub = _parseElement(lst[0]) as URIRef;
          pre = _parseElement(lst[1]) as URIRef;
          obj = _parseElement(lst[2]);
          add(Triple(sub: sub, pre: pre, obj: obj));
        } else if (lst.length == 2 + 1) {
          pre = _parseElement(lst[0]) as URIRef;
          obj = _parseElement(lst[1]);
          add(Triple(sub: sub, pre: pre, obj: obj));
        } else if (lst.length == 1 + 1) {
          obj = _parseElement(lst[0]);
          add(Triple(sub: sub, pre: pre, obj: obj));
        } else {
          throw Exception('Error: illegal line ending with "." $line');
        }
      } else {
        // TODO: Decide if it's an empty line or starts with '#', just ignore it
        //       or throw an [Exception].
        // throw Exception('Error: cannot parse line $line');
      }
      return {'prefix': false, 'sub': sub, 'pre': pre};
    }
  }

  /// Stores prefixes to contexts map first.
  @Deprecated('Use [Graph.addPrefixToCtx] instead.')
  void _parsePrefix(String prefixLine) {
    String k = '';
    String v = '';
    if (!prefixLine.startsWith('@') || !prefixLine.endsWith('.')) {
      throw Exception('Error: Illegal prefix $prefixLine');
    } else if (prefixLine.toLowerCase().startsWith('@prefix') &&
        prefixLine.endsWith('.')) {
      // Example:
      // ['@prefix', 'owl:', '<http://abc.com>', '.']
      List<String> lst = prefixLine.split(' ');

      // Not considering the trailing single ':' (be aware of a single ':')
      k = lst[1].substring(0, lst[1].length - 1);
      v = lst[2].substring(1, lst[2].length - 1);

      // Single ':'
      if (k.length == 0) {
        k = BaseType.shorthandBase.name;
      }
    } else if (prefixLine.toLowerCase().startsWith('@base') &&
        prefixLine.endsWith('.')) {
      List<String> lst = prefixLine.split(' ');
      k = BaseType.defaultBase.name;
      v = lst[1].substring(1, lst[1].length - 1);
    } else {
      throw Exception('Error: unable to parse this line $prefixLine');
    }
    // Valid URI should end with / or # in the angle brackets.
    if (!v.endsWith('/') && !v.endsWith('#')) {
      v += '/';
    }

    // Update contexts, adding to triple will be handled by line.
    contexts[k] = v;
  }

  /// Convert a string to a [URIRef] format.
  ///
  /// Examples:
  /// 1. Parses form such as <http://www.w3.org/2002/07/owl#>
  /// 2. Parses form such as xsd:string to full URIRef
  URIRef _toFullUriref(String s) {
    // Case 1: <uri>
    if (s.startsWith('<') && s.endsWith('>')) {
      String content = s.substring(1, s.length - 1);

      // Case 1.1 <uri> is a valid uri
      if (URIRef.isValidUri(content)) {
        return URIRef(content);
      } else {
        // Case 1.2 <uri> uses base as a default. E.g., <bob> in the following:
        // @base <www.example.com/> .
        // <bob#me> rdf:type owl:NamedIndividual
        return URIRef(contexts[BaseType.defaultBase.name]! + content);
      }
    } else if (s.contains(':')) {
      // Case 2: ':'
      if (':'.allMatches(s).length != 1) {
        throw Exception('Error: $s does not have ":" or too many ":"');
      } else {
        // Case 2.1 'a:b'
        List<String> lst = s.split(':');
        if (lst.length > 1) {
          String vocab = lst[0];
          String type = lst[1];
          if (!contexts.containsKey(vocab)) {
            throw Exception('Error: $vocab not existed in contexts!');
          } else {
            return URIRef(contexts[vocab]! + type);
          }
        } else {
          // Case 2.2 ':a'
          return URIRef(contexts[BaseType.shorthandBase.name]! + lst[0]);
        }
      }
    } else {
      throw Exception('Error: unable to convert $s to URIRef');
    }
  }

  /// Parses single element in a triple or prefix line.
  @Deprecated('Use [Graph.item] instead.')
  dynamic _parseElement(String element) {
    element = element.trim();

    // 1. <element> --> URIRef(element)
    if (element.startsWith('<') && element.endsWith('>')) {
      return _toFullUriref(element);
    } else if ('"'.allMatches(element).length == 2) {
      List<String> lst = element.split('^^');
      String val = lst[0].substring(1, lst[0].length - 1);

      // 2. "val"^^xsd:string
      // Need to consider case like "e.scissorhands@example.org"^^xsd:anyURI
      if (!element.contains('@') ||
          (element.contains('@') && element.split('@')[1].contains('.'))) {
        if (element.contains('^^')) {
          URIRef dType = _toFullUriref(lst[1]);
          return Literal(val, datatype: dType);
        } else {
          /// 3. "val"
          return Literal(val);
        }
      } else {
        // 4. "val"@en (exclude the above case @example.org)
        List<String> lst = element.split('@');
        String val = lst[0].substring(1, lst[0].length - 1);
        String lang = lst[1];
        return Literal(val, lang: lang);
      }
    } else if (element.contains(':')) {
      // 5. abc:def (such as rdf:type)
      return _toFullUriref(element);
    } else if (int.tryParse(element) != null) {
      // 6. single int/double/float without explicit datatype
      return Literal(element, datatype: XSD.int);
    } else if (double.tryParse(element) != null) {
      return Literal(element, datatype: XSD.float);
    }
  }

  /// Parses a valid turtle file read into a string [fileContent].
  ///
  /// Updates [Graph.ctx], [Graph.groups] and [Graph.triples] in the process.
  void parseTurtle(String fileContent) {
    try {
      // Preprocess the content and remove comments.
      String processedContent = _preprocessTurtleContent(fileContent);
      final String content = _removeComments(processedContent);

      // Parse the content into a list of triples.
      List parsedList = parser.parse(content).value;

      // Save context and groups for each triple list.
      for (int i = 0; i < parsedList.length; i++) {
        try {
          _saveToContext(parsedList[i]);
        } catch (e) {
          print(
              'Error in _saveToContext at line ${_findLineNumber(content, parsedList[i])}: $e');
        }
      }

      for (int i = 0; i < parsedList.length; i++) {
        try {
          _saveToGroups(parsedList[i]);
        } catch (e) {
          print(
              'Error in _saveToGroups at line ${_findLineNumber(content, parsedList[i])}: $e');
        }
      }
    } catch (e) {
      String errorMessage = e.toString();
      RegExp regExp = RegExp(r'at (\d+):(\d+)');
      Match? match = regExp.firstMatch(errorMessage);

      if (match != null) {
        int line = int.parse(match.group(1)!);
        int column = int.parse(match.group(2)!);

        List<String> lines =
            fileContent.split(Platform.isWindows ? '\r\n' : '\n');
        String errorLine =
            lines.length >= line ? lines[line - 1] : "Unknown line";

        print('ParserException: $errorMessage');
        print('Error at line $line, column $column:');
        print(errorLine);
      } else {
        print('General error in parsing Turtle content: $e');
      }
    }
  }

  /// Parses a valid turtle file from a web link [webLink].
  ///
  /// Updates [Graph.ctx], [Graph.groups] and [Graph.triples] in the process.
  /// The [webLink] should point to a valid Turtle (.ttl) file to ensure correct parsing.
  /// If the [webLink] does not point to a .ttl file, it might cause unexpected parsing errors.
  Future<void> parseTurtleFromWeb(String webLink) async {
    String fileContent = '';

    try {
      // Fetch the content from the web link.
      final response = await http.get(
        Uri.parse(webLink),
      );

      if (response.statusCode == 200) {
        fileContent = utf8.decode(response.bodyBytes);

        // Parse the Turtle content.
        parseTurtle(fileContent);
      } else {
        print(
            'Failed to load content from $webLink. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to load content from $webLink. Error: $e');
    }
  }

  /// Finds the line number of a given triple in the content.
  ///
  /// This is a helper method to aid in error reporting by providing the line number.
  int _findLineNumber(String content, List tripleList) {
    // Convert the content into lines
    List<String> lines = content.split(Platform.isWindows ? '\r\n' : '\n');

    // Convert the triple list back to a string to search for in the lines.
    String tripleString = tripleList.toString();

    // Find the line that contains the triple string.
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains(tripleString)) {
        return i + 1; // Line numbers are 1-based.
      }
    }

    // Return -1 if the triple string is not found (should not happen in well-formed Turtle content)
    return -1;
  }

  /// Saves triples to [Graph.groups].
  ///
  /// Each group corresponds to a group of triples ending with .
  /// Note:
  /// Parsed triples are saved in the list and in the form of
  /// [[sub, [pre1, [obj1, obj2, ...]], [pre2, [obj3, ...]], ...], .]
  /// so the first item is a list of triple content, and the second is just .
  void _saveToGroups(List tripleList) {
    // Skips namespace prefixes as they are handled by [Graph._saveToContext]
    if (tripleList[0] == '@prefix' || tripleList[0] == '@base') {
      return;
    }
    List tripleContent = tripleList[0];
    dynamic sub = item(tripleContent[0]);
    if (!groups.containsKey(sub)) {
      groups[sub] = Map();
    }
    List predicateObjectLists = tripleContent[1];
    for (List predicateObjectList in predicateObjectLists) {
      // Predicate is always an iri.
      // Uses URIRef as we translate PrefixedName to full form of [URIRef]
      dynamic pre = item(predicateObjectList[0]);
      groups[sub]![pre] = Set();
      List objectList = predicateObjectList[1];

      for (var obj in objectList) {
        var objItem;
        if (obj is String) {
          objItem = item(obj);
        } else if (obj is List) {
          objItem = itemFromList(obj);
        }

        groups[sub]![pre]!.add(objItem);
        triples.add(Triple(sub: sub, pre: pre, obj: objItem));

//       for (var obj in objectList) {
//         var parsedObj =
//             (obj is List) ? item(_combineListItems(obj)) : item(obj);
//         groups[sub]![pre]!.add(parsedObj);
//         triples.add(Triple(sub: sub, pre: pre, obj: parsedObj));

      }

      // // Original for loop - TODO remove
      // for (String obj in objectList) {
      //   groups[sub]![pre]!.add(item(obj));
      //   triples.add(Triple(sub: sub, pre: pre, obj: item(obj)));
      // }
    }
  }

  /// Saves prefix lists to ctx map [Graph.ctx].
  void _saveToContext(List tripleList) {
    if (tripleList[0] == '@prefix') {
      String prefixedName = tripleList[1];
      URIRef namespace = item(tripleList[2]) as URIRef;
      ctx[prefixedName] = namespace;
    } else if (tripleList[0] == '@base' && !ctx.containsKey(':')) {
      // Note: there might a conflict between '@prefix : <> .' and '@base <> .'
      ctx[BASE] = item(tripleList[1]) as URIRef;
    }
  }

  /// Converts a string to its corresponding URIRef, or Literal form.
  ///
  /// Examples:
  /// Case 0: 'a' -> RDF.type
  /// Case 1: '<content>' -> URIRef('<content>')
  /// Case 2: :abc -> URIRef(base+abc)
  /// Case 3: abc:efg -> Use prefix abc for a full URIRef
  /// Case 4: abc^^xsd:string -> Literal('abc', datatype:xsd:string)
  /// Case 5: abc@en -> Literal('abc', lang:'en')
  /// Case 6: abc -> Literal('abc')
  item(dynamic s) {
    if (s is String) {
      s = s.trim();

      // 0. a is short for rdf:type
      if (s == 'a') {
        _saveToContext(['@prefix', 'rdf:', '<${RDF.rdf}>']);
        return a;
      }
      // 1. <>
      else if (s.startsWith('<') && s.endsWith('>')) {
        String uri = s.substring(1, s.length - 1);
        return URIRef(uri);
      }
      // 4. abc^^xsd:string
      // Note this needs to come before :abc or abc:efg cases.
      else if (s.contains('^^')) {
        List<String> lst = s.split('^^');
        String value = lst[0];
        String datatype = lst[1];
        // Note: Literal only supports XSD, OWL namespaces currently
        return Literal(value, datatype: item(datatype));
      }
      // 2. :abc
      else if (s.startsWith(':')) {
        // When using @base.
        if (ctx[':'] == null) {
          throw Exception('Base is not defined yet. (caused by $s)');
        }
        return URIRef('${ctx[":"]!.value}${s.substring(1)}');
      }
      // 3. abc:efg
      else if (s.contains(':') && !s.startsWith('_:')) {
        // When using @prefix
        int firstColonPos = s.indexOf(':');
        String namespace = s.substring(0, firstColonPos + 1); // including ':'
        String localname = s.substring(firstColonPos + 1);
        // If the namespace is not defined, we can't proceed.
        if (ctx[namespace] == null) {
          throw Exception(
              'Namespace ${namespace.substring(0, namespace.length - 1)} is used '
              'but not defined. (caused by $s)');
        }
        return URIRef('${ctx[namespace]?.value}$localname');
      }
      // 5. abc@en
      else if (_existsLangTag(s)) {
        String lang = _getLangTag(s);
        String value = s.replaceAll('@$lang', '');
        return Literal(value, lang: lang);
      }
      // AV-20240621: commenting the following and adding above
      // as the following will identify non language tags as well
      // else if (s.contains('@')) {
      //   List<String> lst = s.split('@');
      //   String value = lst[0];
      //   String lang = lst[1];
      //   return Literal(value, lang: lang);
      // }
      // 6. _:
      else if (s.startsWith('_:')) {
        return BNode(s);
      } else {
        // Treat it as a normal string.
        return Literal(s);
      }
    } else if (s is List) {
      // Combine all items and sub-items in the list into a single string.
      String combinedString = _combineListItems(s);
      if (combinedString.startsWith('_:')) {
        return BNode(combinedString);
      }
      return item(combinedString);
    }
  }

  List stripBrackets(List values) {
    if (values[0] == '(' || values[0] == '[') {
      values = values.sublist(1, values.length - 1);
    }
    return values;
  }

  Set parseObjectValues(List objVals) {
    /// Parses a Set or List of multiple object values
    objVals = stripBrackets(objVals)[0];

    Set values = {};
    for (var objVal in objVals) {
      if (objVal is List) {
        objVal = stripBrackets(objVal)[0][0];

        String objName = objVal[0];
        List subValues = objVal[1];

        // TODO try to parse to int/float etc
        Map objMap = {
          item(objName): subValues.length == 1
              ? item(subValues[0])
              : subValues.map((e) => item(e)).toSet()
        };
        values.add(objMap);
      } else {
        // TODO
        values.add(objVal);
      }
    }
    return values;
  }

  List parseObjectValueFromNameStringAndValueList(List obj) {
    /// Used for getting name and values for objects when obj is in the format:
    /// ['Object name string', ['Value 1', 'Value 2 (optional)'...] ]
    /// Returns in format: {'Object name string': {'Value 1', 'Value 2 (optional)'...} }

    String objName = obj[0];

    List values = obj[1];
    Set objValues = {};

    if (values.length == 1) {
      objValues.add(values[0]);
    } else {
      // TODO parse multiple values
      // List singleValuesList = values[1];
      for (final val in values) {
        // check whether string or list
        if (val is String) {
          objValues.add(val);
        } else {
          // TODO
          throw UnimplementedError(
              'Parsing of multiple values is not yet implemented in this method');
        }
      }
    }

    return [objName, objValues];
  }

  parseObjectValue() {
    /// Parses a single object value
  }

  Map<URIRef, Set<dynamic>> itemFromList(List tripleList) {
    List predicateObjectLists = [];
    Map<URIRef, Set<dynamic>> objectGroups = Map();

    if (tripleList[0] == '(') {
      if (tripleList[1][0] is List) {
        tripleList = tripleList[1][0];
      }
    }

    if (tripleList[0] == '[') {
      // trim leading and trailing 'entries' that are just [ or ]
      tripleList = tripleList.sublist(1, tripleList.length - 1);
      predicateObjectLists = tripleList[0];
    }

    for (List predicateObjectList in predicateObjectLists) {
      if (predicateObjectList[0] == '[') {
        predicateObjectList =
            predicateObjectList.sublist(1, predicateObjectList.length - 1);
      }
      var pre;
      pre = item(predicateObjectList[0]);
      var objValues = predicateObjectList[1];

      if (predicateObjectList[0] is List) {
        // detect list within predicateObjectList and iterate
        pre = itemFromList(predicateObjectList[0]);
      } else {
        pre = item(predicateObjectList[0]); // URIRef
      }

      Set objItem = {};

      for (final obj in objValues) {
        if (objValues[0] is List && objValues[0].length > 1) {
          // Multiple object values found (e.g. multiple restrictions on a ConstrainedDatatype)
          objItem.add(parseObjectValues(objValues[0]));
        } else {
          objItem.add(item(obj));
        }
      }

      objectGroups[pre] = objItem;
    }
    return objectGroups;
  }

  /// Serializes the graph to certain format and export to file.
  ///
  /// Note:
  /// [format] now only supports turtle ttl, and [abbr] is used to output cleaner string
  void serialize({String format = 'ttl', String? dest, String? abbr}) {
    String indent = ' ' * 4;

    // New abbr option to work with new method parseTurtle.
    if (abbr != null) {
      if (serializedString != '') {
        serializedString = '';
      }
      serializedString += _serializedContext();
      serializedString += _serializedGroups();
    }

    if (dest != null) {
      var output = StringBuffer();
      // 1. Read and write every prefix.
      _writePrefixes(output);
      // 2. Read and write every graph.
      _writeGraphs(output, indent);
    }
  }

  /// Writes different graphs with various triples to output
  @Deprecated('Use serialization methods instead.')
  void _writeGraphs(StringBuffer output, String indent) {
    String line = '';
    for (var k in graphs.keys) {
      output.write(Platform.isWindows ? '\r\n' : '\n');
      bool isNewGraph = true;
      Set<Triple>? g = graphs[k];
      for (Triple t in g!) {
        if (isNewGraph) {
          isNewGraph = !isNewGraph;
          String firstHalf =
              '${_abbrUrirefToTtl(t.sub, contexts)} ${_abbrUrirefToTtl(t.pre, contexts)}';
          if (t.obj.runtimeType == String) {
            line = '$firstHalf "${t.obj}" ;';
          } else if (t.obj.runtimeType == Literal) {
            // Case: Literal
            Literal o = t.obj as Literal;
            line = '$firstHalf ${o.toTtl()} ;';
          } else if (t.obj.runtimeType == URIRef) {
            // Case: URIRef
            URIRef o = t.obj as URIRef;
            line = '$firstHalf ${_abbrUrirefToTtl(o, contexts)} ;';
          } else {
            line = '$firstHalf ${t.obj} ;';
          }
        } else {
          line += Platform.isWindows ? '\r\n' : '\n';
          String firstHalf = '$indent${_abbrUrirefToTtl(t.pre, contexts)}';
          if (t.obj.runtimeType == String) {
            line += '$firstHalf "${t.obj}" ;';
          } else if (t.obj.runtimeType == Literal) {
            // Case: Literal
            Literal o = t.obj as Literal;
            line += '$firstHalf ${o.toTtl()} ;';
          } else if (t.obj.runtimeType == URIRef) {
            // Case: URIRef
            URIRef o = t.obj as URIRef;
            line += '$firstHalf ${_abbrUrirefToTtl(o, contexts)} ;';
          } else {
            line += '$firstHalf ${t.obj} ;';
          }
        }
      }
      if (line.endsWith(';')) {
        line = line.substring(0, line.length - 1) + '.\n';
      }
      output.write(line);
    }
  }

  /// Abbreviates URIRef or Literal to shorthand form.
  ///
  /// Examples:
  /// 1. URIRef(http://www.w3.org/2001/XMLSchema#numeric) -> xsd:numeric
  /// 2. Literal(56.7, datatype: URIRef(http://www.w3.org/2001/XMLSchema#float))
  ///    -> "56.7"^^xsd:float
  String _abbr(dynamic dy) {
    if (dy.runtimeType == URIRef) {
      if (dy == RDF.type) {
        return 'a';
      }
      dy = dy as URIRef;
      for (String abbr in ctx.keys) {
        URIRef ns = ctx[abbr]!;
        if (dy.inNamespace(Namespace(ns: ns.value))) {
          if (abbr == BASE) {
            // @base <www.example.org/> .
            // <bob#me> a rdf:Person .
            return '<${dy.value.substring(ns.value.length)}';
          } else if (abbr != ':') {
            return '$abbr${dy.value.substring(ns.value.length)}';
          } else {
            // If it's a shorthand form, just surround it with <>
            // @prefix : <www.example2.org/>
            // :alice a rdf:Person
            return ':${dy.value.substring(ns.value.length)}';
          }
        }
      }
      return '<${dy.value}>';
    } else if (dy.runtimeType == Literal) {
      dy = dy as Literal;
      return dy.toTtl();
    }
    // Default case is returning its string back.
    return dy.toString();
  }

  /// Reads and write prefixes.
  @Deprecated('Use serialization methods instead.')
  void _writePrefixes(StringBuffer output) {
    String line = '';
    for (var c in contexts.keys) {
      if (c == BaseType.shorthandBase.name) {
        // Shorthand ':' has no prefixed word.
        line = '@prefix : <${contexts[c]}> .\n';
      } else if (c == BaseType.defaultBase.name) {
        // Default base syntax.
        line = '@base <${contexts[c]}> .\n';
      } else {
        // Usual prefix syntax.
        line = '@prefix $c: <${contexts[c]}> .\n';
      }
      output.write(line);
    }
  }

  /// Gets the well-formatted serialized prefixes.
  String _serializedContext() {
    String rtnStr = '';
    for (var key in ctx.keys) {
      // Note the difference between @base and @prefix.
      if (key == BASE) {
        rtnStr += '@base <${ctx[key]?.value}> .\n';
      } else {
        rtnStr += '@prefix $key <${ctx[key]?.value}> .\n';
      }
    }
    // Add a new empty line before all the triples.
    rtnStr += Platform.isWindows ? '\r\n' : '\n';
    return rtnStr;
  }

  /// Gets the well-formatted serialized triples with commas and semi-colons.
  String _serializedGroups() {
    String rtnStr = '';
    // Subject is in form of URIRef currently.
    for (URIRef sub in groups.keys) {
      String subStr = _abbr(sub);
      rtnStr += '$subStr\n';
      for (URIRef pre in groups[sub]!.keys) {
        // Leave an indent for readability.
        rtnStr += ' ' * 4;
        String preStr = _abbr(pre);
        rtnStr += '$preStr ';
        for (var obj in groups[sub]![pre]!) {
          String objStr = _abbr(obj);
          rtnStr += '$objStr, ';
        }
        // Remove the last ,
        rtnStr = rtnStr.substring(0, rtnStr.length - 2);
        // Start a new line
        rtnStr += ' ;\n';
      }
      // Remove the last ;\n
      rtnStr = rtnStr.substring(0, rtnStr.length - 2);
      rtnStr += '.\n';
    }
    return rtnStr;
  }

  /// Abbreviates [URIRef] in the namespace to bound short name for better
  /// readability in serialization.
  ///
  /// Note:
  /// This is useful when serializing and exporting to files to turtle
  String _abbrUrirefToTtl(URIRef uriRef, Map<String, String> ctx) {
    for (String abbr in ctx.keys) {
      String ns = ctx[abbr]!;
      if (uriRef.inNamespace(Namespace(ns: ns))) {
        // If there are duplicates namespaces for different ctx keys, whichever
        // comes first will take precedence
        if (abbr == BaseType.defaultBase.name) {
          return '<${uriRef.value.substring(ns.length)}>';
        } else if (abbr == BaseType.shorthandBase.name) {
          return ':${uriRef.value.substring(ns.length)}';
        }
        return '$abbr:${uriRef.value.substring(ns.length)}';
      }
    }
    return '<${uriRef.value}>';
  }

  /// Replaces any lines that has #<space> with content shown before.
  ///
  /// Note:
  /// Current implementation is to match and replace line by line
  String _removeComments(String fileContent) {
    String rtnStr = '';
    List<String> lines = fileContent.split(Platform.isWindows ? '\r\n' : '\n');
    for (var line in lines) {
      // See also: https://www.w3.org/TR/turtle/#sec-grammar-comments
      // comments in Turtle take the form of '#', outside an IRIREF or String,
      // and continue to the end of line.
      // Note to include a whitespace to exclude cases like <www.ex.org/bob#me>
      if (line.startsWith('#')) {
        continue;
      }
      rtnStr += line.replaceAll(RegExp(r'\s*#\s.*$'), '');
      rtnStr += Platform.isWindows ? '\r\n' : '\n';
    }
    return rtnStr;
  }

  /// Preprocesses Turtle content to handle multiline string literals.
  ///
  /// This function addresses the issue of multiline literals in Turtle syntax,
  /// which are enclosed within triple quotes `"""`.
  String _preprocessTurtleContent(String turtleContent) {
    // Regular expression to match multiline literals.

    final multilineLiteralRegex = RegExp(
        turtleContent.contains("'''") ? r"'''(.*?)'''" : r'"""(.*?)"""',
        dotAll: true);

    // Replace each multiline literal with a processed version.

    return turtleContent.replaceAllMapped(multilineLiteralRegex, (match) {
      // Get the multiline literal, excluding the triple quotes.

      String multilineLiteral = match.group(1)!;

      // Process the multiline literal as needed.
      // Example: Replace line breaks with a special sequence.

      String processedLiteral = multilineLiteral.replaceAll(
          Platform.isWindows ? '\r\n' : '\n',
          Platform.isWindows ? r'\r\n' : r'\n');

      processedLiteral = processedLiteral.replaceAll('"', '\\"');

      // Return the processed literal with the original triple quotes
      return '"$processedLiteral"';
    });
  }

  /// Check if a language tag exists in a given literal
  bool _existsLangTag(String literal) {
    return langTags.any((element) => literal.contains('@$element'));
  }

  /// Extract the language tag from a given literal
  String _getLangTag(String literal) {
    return langTags.lastWhere((element) => literal.contains('@$element'));
  }

  /// Recursively combines all items in a list and its sub-items into a single string.
  ///
  /// This function traverses a list and concatenates all its elements,
  /// including elements of nested lists, into a single string.
  /// It handles various data types by converting them to their string representations.
  ///
  String _combineListItems(dynamic item) {
    if (item is List) {
      // Recursively call combineListItems on each sub-item and join them into a single string.
      return item.map((subItem) => _combineListItems(subItem)).join('');
    } else {
      // Convert non-list item to a string.
      return item.toString();
    }
  }
}
