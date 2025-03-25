import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final String uuid;
  final String outgoingRequest;
  final bool hasButton;
  final Function(String userId, String userName) onButtonPressed;

  const UserTile({
    super.key, 
    required this.user,
    required this.uuid,
    required this.outgoingRequest,
    this.hasButton = false,
    required this.onButtonPressed,
  });

  String getButtonText(Map<String, dynamic> user, String uuid, String outgoingRequest) {
    // Customize this logic based on your business logic
    if (outgoingRequest == "Add") {
      return "Add";
    } else if (outgoingRequest == "Message") {
      return "Message";
    } else {
      return "Connect";
    }
  }

  @override
  Widget build(BuildContext context) {
    String profilePicture = user['profile_picture'] ?? 'assets/noprofile.png';
    String buttonText = getButtonText(user, uuid, outgoingRequest);

    return ListTile(
      contentPadding: EdgeInsets.all(0),
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: AssetImage(profilePicture),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.max,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '${user['username']}',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: -0.3,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    color: Color.fromARGB(255, 0, 122, 255),
                    size: 16,
                  )
                ],
              ),
              Text(
                '${user['first_name']} ${user['last_name']}',
                style: TextStyle(
                  color: Color(0xFF76767B),
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  letterSpacing: -0.3,
                  height: 1.4,
                ),
              ),
            ],
          ),
          uuid != user['id'] && hasButton
              ? SizedBox(
                  height: 30,
                  child: ElevatedButton(
                    onPressed: () => onButtonPressed(user['id'], user['first_name']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF1C1C1E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      buttonText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withAlpha(175),
                      ),
                    ),
                  ),
                )
              : SizedBox(),
        ],
      ),
    );
  }
}
