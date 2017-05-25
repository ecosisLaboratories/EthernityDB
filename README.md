# EternityDB
A NoSQL Document based DB implementation on top of the Ethereum Project blockchain.

The driver will use a subset of the BSON binary seralization to store and handle NoSQL documents in Json format.

For the sake of simplicity
--------------------------
The NoSQL implementation accepts only documents with at most 8 level of embedded documents.
The key must also be at most 30 character long.

The maximum amount of bytes that a document can hold is 65536, including the 17 self generated bytes of the uniqueID.

The Query Engine cannot handle nested OR condition.


Reduced BSON grammar and OR operator
-------------
<pre><code>
document	::=	int32 e_list "\x00"	BSON Document. int32 is the total number of bytes comprising the document.
e_list	::=	element e_list
  |	""
element	::=	"\x02" e_name string	         UTF-8 string
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
</code></pre>

The driver will also use some reserved single-byte keys to identify logical operation over the SELECT closure.

The AND operation is identified simply with a " , " that separates the keys of the closure.
In an OR operation the comma separates the single condition of the statement (one of them has to be true to satisfy the operation)

| Key (HEX) | Operation | Required value format | Example |
| --------- | --------- | --------------------- | ------- |
| - | AND | Conditions separated by commas | key1: value1, key2: value2 |
| 0x7c | OR | Array of conditions | '0x7c': [{key1: value1}, {key2: value2}] |

First steps: Deploy a Database
-------------
If you already know a deployed driver, just deploy the database contract referencing to the driver contract address. Otherwise deploy the full system.

<pre><code>
const Web3 = require('web3');
// Connect to Ethereum node
const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));

... // deploy driver, compile database.sol contract get ABI
var dbABI = ... // ABI
var dbBytecode = ... // Bytecode of the database.sol contract
var driverAddress = ... // Address of the driver contract

var dbName = ... // Name of your database
var private = ... // True if only you can insert document, false otherwise
var db = web3.eth.contract(dbABI);

var dbBytecodeConstructed = db.new.getData(dbName, private, driverAddress,
                        {data: '0x' + bytecode});
... // Deploy database
</code></pre>

Create Collections in the Database
-------------
Once the database has been created you can create a collection calling the function "newCollection" of your fresh created database contract.

<pre><code>
const Web3 = require('web3');
// Connect to Ethereum node
const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));

...
var dbABI = ... // ABI
var dbAddress = ... // Address of the db contract

var db = web3.eth.contract(dbABI);
var dbInstance db.at(dbAddress);

var collectionName = // Name of your new collection

var myCallData = db.newCollection.getData(collectionName);
... // Send transaction
</code></pre>

Insert Documents in the Collections
-------------------------------
Now it's possible to insert documents in the new collection.

To do that is required to transform the document from the Json format to BSON forma, then split the BSON bytestring in an array of Hex bytes. Finally send the data to the database contract.

<pre><code>
const Web3 = require('web3');
const BSON = require('bson')
const bson = new BSON();
// Connect to Ethereum node
const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));

...
var dbABI = ... // ABI
var dbAddress = ... // Address of the db contract

var db = web3.eth.contract(dbABI);
var dbInstance db.at(dbAddress);

var query = {"asd": 2000,"foo": {"bar": 19}};
var bsonQuery = bson.serialize(query);
  // some bytestring
var hexQuery = bsonQuery.toString('hex');
  // 3f368a....

var hexArrayQuery = ... // Split the hexQuery in an array of bytes12
  // ["0x3f", "036", "0x8a"]

var collectionName = // Name of the collection where the document has to be stored

var myCallData = db.queryInsert.getData(collectionName, hexArrayQuery);
... // Send transaction
</code></pre>

Query the database
-------------------------------
To query a database is required the same process of the insertion to convert a Json query to a BSON query understandable by the database contract.

<pre><code>
const Web3 = require('web3');
const BSON = require('bson')
const jsonfile = require('jsonfile')
const byteBuffer = require("bytebuffer");

const bson = new BSON();
// Connect to Ethereum node
const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));

...
var dbABI = ... // ABI
var dbAddress = ... // Address of the db contract

var db = web3.eth.contract(dbABI);
var dbInstance db.at(dbAddress);

var query = {"asd": 2000};
var queryWithOr = {"|" [{"asd": 2000}, {"foo": {"bar" : 19}}]};

var bsonQuery = bson.serialize(query); // same for the queryWithOr
  // some bytestring
var hexQuery = bsonQuery.toString('hex');
  // 3f368a....

var hexArrayQuery = ... // Split the hexQuery in an array of bytes12
  // ["0x3f", "036", "0x8a"]

var collectionName = // Name of the collection to query

var i = 0; // Index from which the cursor of the collection should look at the documents (0 is the begin)
var ret = dbInstance.queryFind(collectionName, i, hexArrayQuery);

var uniqueID = ret[0] // id of the document
var atIndex = parseInt(ret[1]) // current index of the cursor (-1 means query failed)
var BSONbytes = ret[2] // data of the document in bytes
  // "0x....."

if (i == -1) { // if
  console.log("No more results\n");
}

var buffer = byteBuffer.fromHex(String(BSONbytes).substr(2))["buffer"];
console.log("Result" + n + ": " + JSON.stringify(bson.deserialize(buffer)));


</code></pre>
