import 'dart:io';

import 'package:rdflib/rdflib.dart';

main() async {
  String filePath = 'example/sample_ttl_6.ttl';
  // Read file content to a local String.
  String fileContents = await File(filePath).readAsStringSync();

  print('-------Original file-------\n$fileContents');

  // Create a graph to read turtle file and store info.
  Graph g = Graph();

  // Parse with the new method [Graph.parseTurtle] instead of [Graph.parse] (deprecated).
  g.parseTurtle(fileContents);

  // Serialize the Graph for output.
  g.serialize(format: 'ttl', abbr: 'short');
  print('-------Serialized String--------\n${g.serializedString}');

  // Print out full format of triples (will use shorthand in serialization/export).
  print('--------All triples in the graph-------');
  for (Triple t in g.triples) {
    print(t);
  }
}
