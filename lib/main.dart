import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import 'dart:io';
import 'package:bubble/bubble.dart';

final googleSignIn = GoogleSignIn();
final analytic = FirebaseAnalytics();
final auth = FirebaseAuth.instance;
final reference = FirebaseDatabase.instance.reference().child('messages');

void main() {
  runApp(FriendlyChatApp());
}

class FriendlyChatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Friendly Chat",
      theme: kDefaultTheme,
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return ChatScreenState();
  }
}

class ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  bool _isComposing = false;

  Future<Null> _ensureLoggedIn() async {
    GoogleSignInAccount user = googleSignIn.currentUser;
    if (user == null) user = await googleSignIn.signInSilently();
    if (user == null) await googleSignIn.signIn();
    analytic.logLogin();
    if (await auth.currentUser() == null) {
      GoogleSignInAuthentication authentication =
          await googleSignIn.currentUser.authentication;
      await auth.signInWithCredential(GoogleAuthProvider.getCredential(
          idToken: authentication.idToken,
          accessToken: authentication.accessToken));
    }
  }

  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).primaryColor),
      child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: <Widget>[
              Container(
                margin: EdgeInsets.symmetric(horizontal: 4.0),
                child: IconButton(
                  icon: Icon(Icons.photo_camera),
                  onPressed: _handleSendImage,
                ),
              ),
              Flexible(
                child: TextField(
                  controller: _textController,
                  onChanged: (String text) {
                    setState(() {
                      _isComposing = text.length > 0;
                    });
                  },
                  onSubmitted: _handleSubmitted,
                  decoration:
                      InputDecoration.collapsed(hintText: "Send a message"),
                ),
              ),
              Container(
                  margin: EdgeInsets.symmetric(horizontal: 4.0),
                  child: IconButton(
                    icon: Icon(Icons.send),
                    onPressed: _isComposing
                        ? () => _handleSubmitted(_textController.text)
                        : null,
                  )),
            ],
          )),
    );
  }

  Future<Null> _handleSubmitted(String text) async {
    _textController.clear();
    setState(() {
      _isComposing = false;
    });
    await _ensureLoggedIn();
    _sendMessage(text, null);
  }


  Future<Null> _handleSendImage() async {
    await _ensureLoggedIn();
    File imageFile = await ImagePicker.pickImage(source: ImageSource.camera);
    int random = Random().nextInt(100000);
    StorageReference ref = FirebaseStorage.instance
        .ref()
        .child("image_$random.jpg");
    StorageUploadTask uploadTask = ref.putFile(imageFile);
    String downloadUrl = await (await uploadTask.onComplete).ref.getDownloadURL();
    _sendMessage(null, downloadUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text("Friendly Chat"),
        elevation: 4.0,
      ),
      body: Container(
          child: Column(
            children: <Widget>[
              Flexible(
                child: FirebaseAnimatedList(
                  query: reference,
                  sort: (a, b) => b.key.compareTo(a.key),
                  padding: EdgeInsets.all(8.0),
                  reverse: true,
                  itemBuilder: (_, DataSnapshot snapshot,
                      Animation<double> animation, int x) {
                    return ChatMessage(
                      snapshot: snapshot,
                      animation: animation,
                    );
                  },
                ),
              ),
              Divider(height: 1.0),
              Container(
                decoration: BoxDecoration(color: Theme.of(context).cardColor),
                child: _buildTextComposer(),
              )
            ],
          ),
          decoration: null),
    );
  }

  void _sendMessage(String text, String imageUrl) {
    reference.push().set({
      "text": text,
      "imageUrl": imageUrl,
      "senderName": googleSignIn.currentUser.displayName,
      "senderPhotoUrl": googleSignIn.currentUser.photoUrl
    });
    analytic.logEvent(name: 'send_message');
  }
}

class ChatMessage extends StatelessWidget {
  ChatMessage({this.snapshot, this.animation});

  final DataSnapshot snapshot;
  final Animation animation;

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      ),
      axisAlignment: 0.0,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        child: googleSignIn.currentUser != null
            ? snapshot.value['senderName'] ==
                    googleSignIn.currentUser.displayName
                ? buildMyRow(context)
                : buildOtherRow(context)
            : buildOtherRow(context),
      ),
    );
  }

  Widget buildMyRow(BuildContext context) {
    return Bubble(
      margin: BubbleEdges.only(top: 2),
      alignment: Alignment.topRight,
      nip: BubbleNip.no,
      color: Colors.grey[100],
      child: Wrap(
        direction: Axis.horizontal,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  snapshot.value['senderName'],
                  style: Theme.of(context).textTheme.subhead,
                ),
                Container(
                  margin: const EdgeInsets.only(top: 5.0),
                  child: snapshot.value['imageUrl'] != null
                      ? Image.network(snapshot.value['imageUrl'], width: 250,)
                      : Text(snapshot.value['text']),
                )
              ],
            ),
          ),
          Container(
            margin: EdgeInsets.only(left: 16.0),
            child: CircleAvatar(
              backgroundImage: NetworkImage(snapshot.value['senderPhotoUrl']),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildOtherRow(BuildContext context) {
    return Bubble(
      margin: BubbleEdges.only(top: 2),
      alignment: Alignment.topLeft,
      nip: BubbleNip.no,
      child: Wrap(
        direction: Axis.horizontal,
        children: <Widget>[
          Container(
            margin: EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              backgroundImage: NetworkImage(snapshot.value['senderPhotoUrl']),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  snapshot.value['senderName'],
                  style: Theme.of(context).textTheme.subhead,
                ),
                Container(
                  margin: const EdgeInsets.only(top: 5.0),
                  child: snapshot.value['imageUrl'] != null
                      ? Image.network(snapshot.value['imageUrl'], width: 250)
                      : Text(snapshot.value['text']),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

final ThemeData kDefaultTheme = new ThemeData(
  primarySwatch: Colors.purple,
  accentColor: Colors.orangeAccent[400],
);
