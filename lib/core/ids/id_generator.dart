import 'package:uuid/uuid.dart';

abstract interface class IdGenerator {
  String next();
}

final class UuidV7Generator implements IdGenerator {
  const UuidV7Generator({this.uuid = const Uuid()});

  final Uuid uuid;

  @override
  String next() => uuid.v7();
}
