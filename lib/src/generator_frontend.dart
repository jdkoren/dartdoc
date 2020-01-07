// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show File;

import 'package:dartdoc/src/generator.dart';
import 'package:dartdoc/src/logging.dart';
import 'package:dartdoc/src/model/model.dart';
import 'package:dartdoc/src/model_utils.dart';
import 'package:dartdoc/src/warnings.dart';
import 'package:path/path.dart' as path;

typedef FileWriter = File Function(String filePath, Object content,
    {bool allowOverwrite, Warnable element});

/// [Generator] that delegates rendering to a [GeneratorBackend] and delegates
/// file creation to a [FileWriter].
class GeneratorFrontEnd implements Generator {
  final GeneratorBackend _generatorBackend;
  final FileWriter _writer;

  // Used in write(). This being not null signals the generator is active.
  String _outputDirectory;

  final StreamController<void> _onFileCreated = StreamController(sync: true);

  @override
  Stream<void> get onFileCreated => _onFileCreated.stream;

  @override
  final Map<String, Warnable> writtenFiles = {};

  GeneratorFrontEnd(this._generatorBackend, this._writer);

  // Implement FileWriter so we can wrap the one given to us.
  File write(String filePath, Object content,
      {bool allowOverwrite, Warnable element}) {
    assert(_outputDirectory != null);
    // Replace '/' separators with proper separators for the platform.
    String outFile = path.joinAll(filePath.split('/'));
    outFile = path.join(_outputDirectory, outFile);
    File file = _writer(outFile, content,
        allowOverwrite: allowOverwrite, element: element);
    writtenFiles[outFile] = element;
    _onFileCreated.add(file);
    return file;
  }

  @override
  Future generate(PackageGraph packageGraph, String outputDirectory) async {
    _outputDirectory = outputDirectory;
    try {
      List<Indexable> indexElements = <Indexable>[];
      _generateDocs(packageGraph, indexElements);
      await _generatorBackend.generateAdditionalFiles(write, packageGraph);

      List<Categorization> categories = indexElements
          .where((e) => e is Categorization && e.hasCategorization)
          .map((e) => e as Categorization)
          .toList();
      _generatorBackend.generateCategoryJson(write, categories);
      _generatorBackend.generateSearchIndex(write, indexElements);
    } finally {
      _outputDirectory = null;
    }
  }

  // Traverses the package graph and collects elements for the search index.
  void _generateDocs(
      PackageGraph packageGraph, List<Indexable> indexAccumulator) {
    if (packageGraph == null) return;

    logInfo('documenting ${packageGraph.defaultPackage.name}');
    _generatorBackend.generatePackage(
        write, packageGraph, packageGraph.defaultPackage);

    for (var package in packageGraph.localPackages) {
      for (var category in filterNonDocumented(package.categories)) {
        logInfo('Generating docs for category ${category.name} from '
            '${category.package.fullyQualifiedName}...');
        indexAccumulator.add(category);
        _generatorBackend.generateCategory(write, packageGraph, category);
      }

      for (var lib in filterNonDocumented(package.libraries)) {
        logInfo('Generating docs for library ${lib.name} from '
            '${lib.element.source.uri}...');
        if (!lib.isAnonymous && !lib.hasDocumentation) {
          packageGraph.warnOnElement(lib, PackageWarning.noLibraryLevelDocs);
        }
        indexAccumulator.add(lib);
        _generatorBackend.generateLibrary(write, packageGraph, lib);

        for (var clazz in filterNonDocumented(lib.allClasses)) {
          indexAccumulator.add(clazz);
          _generatorBackend.generateClass(write, packageGraph, lib, clazz);

          for (var constructor in filterNonDocumented(clazz.constructors)) {
            if (!constructor.isCanonical) continue;

            indexAccumulator.add(constructor);
            _generatorBackend.generateConstructor(
                write, packageGraph, lib, clazz, constructor);
          }

          for (var constant in filterNonDocumented(clazz.constants)) {
            if (!constant.isCanonical) continue;

            indexAccumulator.add(constant);
            _generatorBackend.generateConstant(
                write, packageGraph, lib, clazz, constant);
          }

          for (var property in filterNonDocumented(clazz.staticProperties)) {
            if (!property.isCanonical) continue;

            indexAccumulator.add(property);
            _generatorBackend.generateProperty(
                write, packageGraph, lib, clazz, property);
          }

          for (var property in filterNonDocumented(clazz.allInstanceFields)) {
            if (!property.isCanonical) continue;

            indexAccumulator.add(property);
            _generatorBackend.generateProperty(
                write, packageGraph, lib, clazz, property);
          }

          for (var method in filterNonDocumented(clazz.allInstanceMethods)) {
            if (!method.isCanonical) continue;

            indexAccumulator.add(method);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, clazz, method);
          }

          for (var operator in filterNonDocumented(clazz.allOperators)) {
            if (!operator.isCanonical) continue;

            indexAccumulator.add(operator);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, clazz, operator);
          }

          for (var method in filterNonDocumented(clazz.staticMethods)) {
            if (!method.isCanonical) continue;

            indexAccumulator.add(method);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, clazz, method);
          }
        }

        for (var extension in filterNonDocumented(lib.extensions)) {
          indexAccumulator.add(extension);
          _generatorBackend.generateExtension(
              write, packageGraph, lib, extension);

          for (var constant in filterNonDocumented(extension.constants)) {
            indexAccumulator.add(constant);
            _generatorBackend.generateConstant(
                write, packageGraph, lib, extension, constant);
          }

          for (var property
              in filterNonDocumented(extension.staticProperties)) {
            indexAccumulator.add(property);
            _generatorBackend.generateProperty(
                write, packageGraph, lib, extension, property);
          }

          for (var method
              in filterNonDocumented(extension.allPublicInstanceMethods)) {
            indexAccumulator.add(method);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, extension, method);
          }

          for (var method in filterNonDocumented(extension.staticMethods)) {
            indexAccumulator.add(method);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, extension, method);
          }

          for (var operator in filterNonDocumented(extension.allOperators)) {
            indexAccumulator.add(operator);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, extension, operator);
          }

          for (var property
              in filterNonDocumented(extension.allInstanceFields)) {
            indexAccumulator.add(property);
            _generatorBackend.generateProperty(
                write, packageGraph, lib, extension, property);
          }
        }

        for (var mixin in filterNonDocumented(lib.mixins)) {
          indexAccumulator.add(mixin);
          _generatorBackend.generateMixin(write, packageGraph, lib, mixin);

          for (var constructor in filterNonDocumented(mixin.constructors)) {
            if (!constructor.isCanonical) continue;

            indexAccumulator.add(constructor);
            _generatorBackend.generateConstructor(
                write, packageGraph, lib, mixin, constructor);
          }

          for (var constant in filterNonDocumented(mixin.constants)) {
            if (!constant.isCanonical) continue;
            indexAccumulator.add(constant);
            _generatorBackend.generateConstant(
                write, packageGraph, lib, mixin, constant);
          }

          for (var property in filterNonDocumented(mixin.staticProperties)) {
            if (!property.isCanonical) continue;

            indexAccumulator.add(property);
            _generatorBackend.generateConstant(
                write, packageGraph, lib, mixin, property);
          }

          for (var property in filterNonDocumented(mixin.allInstanceFields)) {
            if (!property.isCanonical) continue;

            indexAccumulator.add(property);
            _generatorBackend.generateConstant(
                write, packageGraph, lib, mixin, property);
          }

          for (var method in filterNonDocumented(mixin.allInstanceMethods)) {
            if (!method.isCanonical) continue;

            indexAccumulator.add(method);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, mixin, method);
          }

          for (var operator in filterNonDocumented(mixin.allOperators)) {
            if (!operator.isCanonical) continue;

            indexAccumulator.add(operator);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, mixin, operator);
          }

          for (var method in filterNonDocumented(mixin.staticMethods)) {
            if (!method.isCanonical) continue;

            indexAccumulator.add(method);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, mixin, method);
          }
        }

        for (var eNum in filterNonDocumented(lib.enums)) {
          indexAccumulator.add(eNum);
          _generatorBackend.generateEnum(write, packageGraph, lib, eNum);

          for (var property in filterNonDocumented(eNum.allInstanceFields)) {
            indexAccumulator.add(property);
            _generatorBackend.generateConstant(
                write, packageGraph, lib, eNum, property);
          }
          for (var operator in filterNonDocumented(eNum.allOperators)) {
            indexAccumulator.add(operator);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, eNum, operator);
          }
          for (var method in filterNonDocumented(eNum.allInstanceMethods)) {
            indexAccumulator.add(method);
            _generatorBackend.generateMethod(
                write, packageGraph, lib, eNum, method);
          }
        }

        for (var constant in filterNonDocumented(lib.constants)) {
          indexAccumulator.add(constant);
          _generatorBackend.generateTopLevelConstant(
              write, packageGraph, lib, constant);
        }

        for (var property in filterNonDocumented(lib.properties)) {
          indexAccumulator.add(property);
          _generatorBackend.generateTopLevelProperty(
              write, packageGraph, lib, property);
        }

        for (var function in filterNonDocumented(lib.functions)) {
          indexAccumulator.add(function);
          _generatorBackend.generateFunction(
              write, packageGraph, lib, function);
        }

        for (var typeDef in filterNonDocumented(lib.typedefs)) {
          indexAccumulator.add(typeDef);
          _generatorBackend.generateTypeDef(write, packageGraph, lib, typeDef);
        }
      }
    }
  }
}

abstract class GeneratorBackend {
  /// Emit json describing the [categories] defined by the package.
  void generateCategoryJson(FileWriter writer, List<Categorization> categories);

  /// Emit json catalog of [indexedElements] for use with a search index.
  void generateSearchIndex(FileWriter writer, List<Indexable> indexedElements);

  /// Emit documentation content for the [package].
  void generatePackage(FileWriter writer, PackageGraph graph, Package package);

  /// Emit documentation content for the [category].
  void generateCategory(
      FileWriter writer, PackageGraph graph, Category category);

  /// Emit documentation content for the [library].
  void generateLibrary(FileWriter writer, PackageGraph graph, Library library);

  /// Emit documentation content for the [clazz].
  void generateClass(
      FileWriter writer, PackageGraph graph, Library library, Class clazz);

  /// Emit documentation content for the [eNum].
  void generateEnum(
      FileWriter writer, PackageGraph graph, Library library, Enum eNum);

  /// Emit documentation content for the [mixin].
  void generateMixin(
      FileWriter writer, PackageGraph graph, Library library, Mixin mixin);

  /// Emit documentation content for the [constructor].
  void generateConstructor(FileWriter writer, PackageGraph graph,
      Library library, Class clazz, Constructor constructor);

  /// Emit documentation content for the [field].
  void generateConstant(FileWriter writer, PackageGraph graph, Library library,
      Container clazz, Field field);

  /// Emit documentation content for the [field].
  void generateProperty(FileWriter writer, PackageGraph graph, Library library,
      Container clazz, Field field);

  /// Emit documentation content for the [method].
  void generateMethod(FileWriter writer, PackageGraph graph, Library library,
      Container clazz, Method method);

  /// Emit documentation content for the [extension].
  void generateExtension(FileWriter writer, PackageGraph graph, Library library,
      Extension extension);

  /// Emit documentation content for the [function].
  void generateFunction(FileWriter writer, PackageGraph graph, Library library,
      ModelFunction function);

  /// Emit documentation content for the [constant].
  void generateTopLevelConstant(FileWriter writer, PackageGraph graph,
      Library library, TopLevelVariable constant);

  /// Emit documentation content for the [property].
  void generateTopLevelProperty(FileWriter writer, PackageGraph graph,
      Library library, TopLevelVariable property);

  /// Emit documentation content for the [typedef].
  void generateTypeDef(
      FileWriter writer, PackageGraph graph, Library library, Typedef typedef);

  /// Emit files not specific to a Dart language element.
  void generateAdditionalFiles(FileWriter writer, PackageGraph graph);
}
