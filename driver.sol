pragma solidity ^0.4.11;

/*
//////////////////////////////////////////////////////////////////////////////
////////////// Grammar BSON (reduced)
//////////////////////////////////////////////////////////////////////////////
document	::=	int32 e_list "\x00"	BSON Document. int32 is the total number of bytes comprising the document.
e_list	::=	element e_list
  |	""
element	::=	"\x01" e_name double	 64-bit binary floating point
  |	"\x02" e_name string	         UTF-8 string
  |	"\x03" e_name document	       Embedded document
  |	"\x04" e_name document	       Array
  |	"\x07" e_name (byte*12)	       ObjectId
  |	"\x08" e_name "\x00"	         Boolean "false"
  |	"\x08" e_name "\x01"	         Boolean "true"
  |	"\x0A" e_name	                 Null value
  |	"\x10" e_name int32	           32-bit integer
  |	"\x11" e_name uint64	         Timestamp
  |	"\x12" e_name int64	           64-bit integer
e_name	::=	cstring	                 Key name
string	::=	int32 (byte*) "\x00"	   String - The int32 is the number bytes in the (byte*) + 1 (for the trailing '\x00'). The (byte*) is zero or more UTF-8 encoded characters.
cstring	::=	(byte*) "\x00"	         Zero or more modified UTF-8 encoded characters followed by '\x00'. The (byte*) MUST NOT contain '\x00', hence it is not full UTF-8.

//////////////////////////////////////////////////////////////////////////////
////////////// Operations
//////////////////////////////////////////////////////////////////////////////
, = AND
"\x6F" = OR
"\x6E" = >
"\x6D" = >=
"\x6C" = <
"\x6B" = <=
"\x6A" = !=

//////////////////////////////////////////////////////////////////////////////
////////////// Insertion Query Example
//////////////////////////////////////////////////////////////////////////////
Bson converter (external) converts a Json in a Bson
  -> from { item: "journal", qty: 25, size: { h: 14, w: 21, uom: "cm" }, rate: 2.3 }
  -> to Binary Bson Data bData
    -> Check that the Bson contains only "allowed data types" (see grammar)
  -> database.queryInsert(collectionName, bData)
  -> Insertion in a new entry with parsing for useful information

//////////////////////////////////////////////////////////////////////////////
////////////// Select Query Example
//////////////////////////////////////////////////////////////////////////////
Allowed operation: = (later <, <=, >, >=, !=)
Follow MongoDB query grammar passing a single Json to the contract that contains
all the clauses.
The only operation on the embeed document and array is the equality, that returns every
document which contains the embeed document provided (not strictly equal):
  -> select({ size: { h: 14 } })
    -> returns the document used in the insert example

  -> select * where qty = 25 or size.h = 15
    -> select("\n6F": [ { qty: 25 }, { size: { h: 25 } } ])

  -> select * where qty = 25 or size.h >= 15
    -> select("\n6F": [ { qty: 25 }, { size: { h: { "\n6D": 25 } } ])
*/
import "lib/stringUtils.sol";
import "bsonparser/documentparser.sol";
import "interfaces.sol";

contract Driver is DriverAbstract {
  using StringUtils for string;
  using DocumentParser for byte[];

  function registerDatabase(address owner, string strName, DBAbstract db) {
    if (address(getDatabase(owner, strName)) != 0x0) throw;
    databasesByName[msg.sender][strName.toBytes32()] = db;
  }

  function getDatabase(address owner, string strName) constant returns (DBAbstract) {
    return databasesByName[owner][strName.toBytes32()];
  }

  function parseDocumentData(byte[] data, DBAbstract db, bytes12 d) {
    int8 documentIndex = -1;
    // For now we let only up to 8 nested document level
    uint64[] memory embeedDocumentStack = new uint64[](8);
    // Skip first 4 BYTE (int32 = Doc length)
    for (uint64 i = 4; i < data.length - 1; i++) {
        // Select parent nodeTree if available
        if (documentIndex >= 0 && embeedDocumentStack[uint8(documentIndex)] <= i) {
          db.setParentDocumentNode(d);
          documentIndex--;
        }

        uint8 bType = 0;
        bytes32 b32Name = 0;
        uint64 nDataLen = 0;
        uint64 nDataStart = 0;
        (bType, b32Name, nDataLen, nDataStart) = data.nextKeyValue(i);

        if (bType == 0x0) {
          continue;
        }

        // check type validity
        if (bType > 0x12 || bType == 0x00 || bType == 0x05  || bType == 0x06 ||
            bType == 0x09  || bType == 0x0B  || bType == 0x0C  || bType == 0x0D ||
            bType == 0x0E  || bType == 0x0F)
            throw;

        db.setKeyIndex(d, b32Name, i + nDataStart);

        if (bType == 0x03 || bType == 0x04) {
          if (documentIndex >= 7) throw;
          db.addEmbeededDocumentNode(d, b32Name);
          embeedDocumentStack[uint8(++documentIndex)] = i + nDataLen - 1;
          i += nDataStart - 1;
        } else {
          i += nDataLen - 1;
        }
    }
  }

  function getUniqueID(byte[] seed) constant returns (bytes12 id) {
    // 4 bit blockSha3
    // 3 bit hash(seed, msg.sender)
    // 2 bit timestamp
    // 3 bit random
    bytes32 blockSha3 = sha3(block.blockhash(block.number - 1), msg.sender);
    bytes32 seedSha3 = sha3(seed, msg.sender);
    bytes32 timeSha3 = sha3(block.timestamp, msg.sender);
    bytes32 randomHash = sha3(sha3(blockSha3, timeSha3), seed);

    for (uint8 j = 0; j < 12; j++) {
      if (j < 4) {
        id |= bytes12(blockSha3[j]) >> (j * 8);
      } else if (j < 7) {
        id |= bytes12(seedSha3[j]) >> (j * 8);
      } else if (j < 9) {
        id |= bytes12(timeSha3[j]) >> (j * 8);
      } else {
        uint8 index = uint8(uint256(randomHash) % 32);
        id |= bytes12(randomHash[index]) >> (j * 8);
        randomHash = sha3(randomHash, seedSha3);
      }
    }
  }
}
