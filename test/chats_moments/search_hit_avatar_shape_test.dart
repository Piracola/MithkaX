//
//  search_hit_avatar_shape_test.dart
//
//  The search page draws the peer's avatar round and a message's own media as
//  a rounded rectangle. A message hit whose only image is the chat photo used
//  to take the media path, so every result in the Messages tab showed the chat
//  avatar as a square.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/search_view.dart';

void main() {
  test('a chat or user result is a peer avatar', () {
    expect(
      searchHitLeadingImageIsPeerAvatar(
        isChatHit: true,
        isUserHit: false,
        isMessageHit: false,
        hasThumbnail: false,
        hasPhoto: true,
      ),
      isTrue,
    );
    expect(
      searchHitLeadingImageIsPeerAvatar(
        isChatHit: false,
        isUserHit: true,
        isMessageHit: false,
        hasThumbnail: false,
        hasPhoto: true,
      ),
      isTrue,
    );
  });

  test('a message result with no media thumb is a peer avatar', () {
    expect(
      searchHitLeadingImageIsPeerAvatar(
        isChatHit: false,
        isUserHit: false,
        isMessageHit: true,
        hasThumbnail: false,
        hasPhoto: true,
      ),
      isTrue,
      reason: 'the only image on a text-message hit is the chat photo',
    );
  });

  test('a message result with its own media keeps the rectangle', () {
    expect(
      searchHitLeadingImageIsPeerAvatar(
        isChatHit: false,
        isUserHit: false,
        isMessageHit: true,
        hasThumbnail: true,
        hasPhoto: true,
      ),
      isFalse,
      reason: 'a photo result must not crop its thumbnail to a circle',
    );
  });

  test('a message result with no image at all falls through to its icon', () {
    expect(
      searchHitLeadingImageIsPeerAvatar(
        isChatHit: false,
        isUserHit: false,
        isMessageHit: true,
        hasThumbnail: false,
        hasPhoto: false,
      ),
      isFalse,
    );
  });
}
