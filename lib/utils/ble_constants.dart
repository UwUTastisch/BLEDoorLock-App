import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleConstants {
// UUIDs for the BLE services
  static Guid uuidUserService = Guid("2ff7c135-5010-497b-a054-cea3984c7cc9");
  static Guid uuidAdminService = Guid("be527357-c722-4367-aac3-bddef6a6f6e2");
  static Guid uuidCryptoService = Guid("1c970e06-8094-4b83-a54b-a465396ebaa8");

// UUIDs for the BLE characteristics for the door opener
  static Guid uuidUserCharacteristic =
  Guid("5d3932fa-2901-4b6b-9f41-7720976a85d4");
  static Guid uuidPassCharacteristic =
  Guid("dd16cad0-a66a-402f-9183-201c20753647");
  static Guid uuidLockStateCharacteristic =
  Guid("05c5653a-7279-406c-9f9e-df72aa99ca2d");

// UUID for the BLE characteristics for encryption
  static Guid uuidKeyCharacteristic = Guid("df5ba2aa-c90c-4c90-8c5f-059f62ff51a1");

// UUIDs for the BLE characteristics for adding a user as admin
  static Guid uuidAdminCharacteristic =
  Guid("68f2b041-dc1e-42af-af96-773a2386b08b");
  static Guid uuidAdminPassCharacteristic =
  Guid("394e8790-109b-47c0-aa67-1aa61c02188b");
  static Guid uuidAddUserCharacteristic =
  Guid("92acb83b-ff02-43ec-9adb-16755eb8ce9b");
  static Guid uuidAddPassCharacteristic =
  Guid("8de8c0c0-0568-40a0-a52b-520a6e772503");
  static Guid uuidAdminActionCharacteristic =
  Guid("b1d86fdf-7d5d-49b7-8da7-b02bd53bdb0a");



}
