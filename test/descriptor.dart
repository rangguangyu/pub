// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Pub-specific test descriptors.
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:pub/src/io.dart';
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test_descriptor/test_descriptor.dart';

import 'descriptor/git.dart';
import 'descriptor/packages.dart';
import 'descriptor/tar.dart';
import 'test_pub.dart';

export 'package:test_descriptor/test_descriptor.dart';
export 'descriptor/git.dart';
export 'descriptor/packages.dart';
export 'descriptor/tar.dart';

/// Creates a new [GitRepoDescriptor] with [name] and [contents].
GitRepoDescriptor git(String name, [Iterable<Descriptor> contents]) =>
    new GitRepoDescriptor(name, contents == null ? <Descriptor>[] : contents);

/// Creates a new [TarRepoDescriptor] with [name] and [contents].
TarFileDescriptor tar(String name, [Iterable<Descriptor> contents]) =>
    new TarFileDescriptor(name, contents == null ? <Descriptor>[] : contents);

/// Describes a package that passes all validation.
Descriptor get validPackage => dir(appPath, [
      libPubspec("test_pkg", "1.0.0", sdk: '>=1.8.0 <=2.0.0'),
      file("LICENSE", "Eh, do what you want."),
      file("README.md", "This package isn't real."),
      dir("lib", [file("test_pkg.dart", "int i = 1;")])
    ]);

/// Returns a descriptor of a snapshot that can't be run by the current VM.
///
/// This snapshot was generated using version 2.0.0-dev.58.0 of the VM.
FileDescriptor outOfDateSnapshot(String name) =>
    file(name, readBinaryFile(testAssetPath('out-of-date.snapshot.dart2')));

/// Describes a file named `pubspec.yaml` with the given YAML-serialized
/// [contents], which should be a serializable object.
///
/// [contents] may contain [Future]s that resolve to serializable objects,
/// which may in turn contain [Future]s recursively.
Descriptor pubspec(Map<String, Object> contents) =>
    file("pubspec.yaml", yaml(contents));

/// Describes a file named `pubspec.yaml` for an application package with the
/// given [dependencies].
Descriptor appPubspec([Map dependencies]) {
  var map = <String, dynamic>{"name": "myapp"};
  if (dependencies != null) map["dependencies"] = dependencies;
  return pubspec(map);
}

/// Describes a file named `pubspec.yaml` for a library package with the given
/// [name], [version], and [deps]. If "sdk" is given, then it adds an SDK
/// constraint on that version.
Descriptor libPubspec(String name, String version,
    {Map deps, Map devDeps, String sdk}) {
  var map = packageMap(name, version, deps, devDeps);
  if (sdk != null) map["environment"] = {"sdk": sdk};
  return pubspec(map);
}

/// Describes a directory named `lib` containing a single dart file named
/// `<name>.dart` that contains a line of Dart code.
Descriptor libDir(String name, [String code]) {
  // Default to printing the name if no other code was given.
  if (code == null) code = name;
  return dir("lib", [file("$name.dart", 'main() => "$code";')]);
}

/// Describes a directory whose name ends with a hyphen followed by an
/// alphanumeric hash.
Descriptor hashDir(String name, Iterable<Descriptor> contents) => pattern(
    new RegExp("$name${r'-[a-f0-9]+'}"), (dirName) => dir(dirName, contents));

/// Describes a directory for a Git package. This directory is of the form
/// found in the revision cache of the global package cache.
Descriptor gitPackageRevisionCacheDir(String name, [int modifier]) {
  var value = name;
  if (modifier != null) value = "$name $modifier";
  return hashDir(name, [libDir(name, value)]);
}

/// Describes a directory for a Git package. This directory is of the form
/// found in the repo cache of the global package cache.
Descriptor gitPackageRepoCacheDir(String name) =>
    hashDir(name, [dir('objects'), dir('refs')]);

/// Describes the `packages/` directory containing all the given [packages],
/// which should be name/version pairs. The packages will be validated against
/// the format produced by the mock package server.
///
/// A package with a null version should not be downloaded.
Descriptor packagesDir(Map<String, String> packages) {
  var contents = <Descriptor>[];
  packages.forEach((name, version) {
    if (version == null) {
      contents.add(nothing(name));
    } else {
      contents
          .add(dir(name, [file("$name.dart", 'main() => "$name $version";')]));
    }
  });
  return dir(packagesPath, contents);
}

/// Describes the global package cache directory containing all the given
/// [packages], which should be name/version pairs. The packages will be
/// validated against the format produced by the mock package server.
///
/// A package's value may also be a list of versions, in which case all
/// versions are expected to be downloaded.
///
/// If [port] is passed, it's used as the port number of the local hosted server
/// that this cache represents. It defaults to [globalServer.port].
///
/// If [includePubspecs] is `true`, then pubspecs will be created for each
/// package. Defaults to `false` so that the contents of pubspecs are not
/// validated since they will often lack the dependencies section that the
/// real pubspec being compared against has. You usually only need to pass
/// `true` for this if you plan to call [create] on the resulting descriptor.
Descriptor cacheDir(Map packages, {int port, bool includePubspecs: false}) {
  var contents = <Descriptor>[];
  packages.forEach((name, versions) {
    if (versions is! List) versions = [versions];
    for (var version in versions) {
      var packageContents = [libDir(name, '$name $version')];
      if (includePubspecs) {
        packageContents.add(libPubspec(name, version));
      }
      contents.add(dir("$name-$version", packageContents));
    }
  });

  return hostedCache(contents, port: port);
}

/// Describes the main cache directory containing cached hosted packages
/// downloaded from the mock package server.
///
/// If [port] is passed, it's used as the port number of the local hosted server
/// that this cache represents. It defaults to [globalServer.port].
Descriptor hostedCache(Iterable<Descriptor> contents, {int port}) {
  return dir(cachePath, [
    dir('hosted', [dir('localhost%58${port ?? globalServer.port}', contents)])
  ]);
}

/// Describes the file in the system cache that contains the client's OAuth2
/// credentials. The URL "/token" on [server] will be used as the token
/// endpoint for refreshing the access token.
Descriptor credentialsFile(ShelfTestServer server, String accessToken,
    {String refreshToken, DateTime expiration}) {
  return dir(cachePath, [
    file(
        'credentials.json',
        new oauth2.Credentials(accessToken,
                refreshToken: refreshToken,
                tokenEndpoint: server.url.resolve('/token'),
                scopes: ['https://www.googleapis.com/auth/userinfo.email'],
                expiration: expiration)
            .toJson())
  ]);
}

/// Describes the application directory, containing only a pubspec specifying
/// the given [dependencies].
DirectoryDescriptor appDir([Map dependencies]) =>
    dir(appPath, [appPubspec(dependencies)]);

/// Describes a `.packages` file.
///
/// [dependencies] maps package names to strings describing where the packages
/// are located on disk. If the strings are semantic versions, then the packages
/// are located in the system cache; otherwise, the strings are interpreted as
/// relative `file:` URLs.
///
/// Validation checks that the `.packages` file exists, has the expected
/// entries (one per key in [dependencies]), each with a path that contains
/// either the version string (for a reference to the pub cache) or a
/// path to a path dependency, relative to the application directory.
Descriptor packagesFile([Map<String, String> dependencies]) =>
    new PackagesFileDescriptor(dependencies);

/// Describes a `.packages` file in the application directory, including the
/// implicit entry for the app itself.
Descriptor appPackagesFile(Map<String, String> dependencies) {
  var copied = new Map<String, String>.from(dependencies);
  copied["myapp"] = ".";
  return dir(appPath, [packagesFile(copied)]);
}
