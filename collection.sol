pragma solidity ^0.4.11;
import "interfaces.sol";

contract Collection is CollectionAbstract {
  mapping (bytes12 => byte[4096]) private documentByID;

  DBAbstract private db;
  bytes12[] private documentIDs;
  uint32[] private documentLengths;
  uint64 private count;
  string private name;

  function Collection(string _name, DBAbstract _db) {
    db = _db;
    name = _name;
  }

  function changeDB(DBAbstract _db) {
    if (msg.sender != address(db)) throw;
    db = _db;
  }

  function getDocumentCount() constant returns (uint64) {
    return count;
  }

  function getName() constant returns (string) {
    return name;
  }

  function getDocumentByteAt(bytes12 id, uint64 i) constant returns (byte) {
    return documentByID[id][i];
  }

  function getDocumentIDbyIndex(uint64 i) constant returns (bytes12) {
    return documentIDs[i];
  }

  function getDocumentLengthbyIndex(uint64 i) constant returns (uint32) {
    return documentLengths[i];
  }

  function insertDocument(bytes12 id, bytes21 head, byte[] data) {
    if (msg.sender != address(db)) throw;
    uint32 i = 0;
    if (head == bytes21(0)) {
      for (; i < 21; i++) {
          documentByID[id][i] = head[i];
      }
      for (i = 4; i < data.length; i++) {
          documentByID[id][i - 4 + 21] = data[i];
      }
      documentLengths[count] = uint32(data.length) - 4 + 21;
    } else {
      for (; i < data.length; i++) {
          documentByID[id][i - 4 + 21] = data[i];
      }
      documentLengths[count] = uint32(data.length);
    }

    documentIDs[count] = id;
    count++;
  }
}
