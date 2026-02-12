# Re-implementation Guide: M3U Account Profile Restrictions

This guide documents the full stack of changes required to implement the feature that allows restricting specific users (XC clients) to specific M3U account profiles.

## 1. Database Model Changes
**File:** `apps/accounts/models.py`

Add the `m3u_profiles` Many-to-Many field to the `User` model.

```python
# ... existing imports ...
class User(AbstractUser):
    # ... existing fields ...
    channel_profiles = models.ManyToManyField(
        "dispatcharr_channels.ChannelProfile",
        blank=True,
        related_name="users",
    )
    # ADD THIS FIELD:
    m3u_profiles = models.ManyToManyField(
        "m3u.M3UAccountProfile",
        blank=True,
        related_name="users",
    )
    user_level = models.IntegerField(default=UserLevel.STREAMER)
    # ...
```

## 2. API Serializer Updates
**File:** `apps/accounts/serializers.py`

Update `UserSerializer` to handle the new field.

```python
# ... existing imports ...
from apps.m3u.models import M3UAccountProfile

class UserSerializer(serializers.ModelSerializer):
    # ... existing fields ...
    # ADD THIS:
    m3u_profiles = serializers.PrimaryKeyRelatedField(
        queryset=M3UAccountProfile.objects.all(), many=True, required=False
    )

    class Meta:
        model = User
        fields = [
            # ... existing fields ...
            "m3u_profiles", # ADD THIS
            # ...
        ]

    def create(self, validated_data):
        # ...
        m3u_profiles = validated_data.pop("m3u_profiles", [])
        user = User(**validated_data)
        # ...
        user.save()
        user.m3u_profiles.set(m3u_profiles) # ADD THIS
        return user

    def update(self, instance, validated_data):
        # ...
        m3u_profiles = validated_data.pop("m3u_profiles", None)
        # ...
        instance.save()
        if m3u_profiles is not None:
            instance.m3u_profiles.set(m3u_profiles) # ADD THIS
        return instance
```

## 3. Core Logic Update (Stream Selection)
**File:** `apps/channels/models.py`

Update the `get_stream` method in the `Channel` model to accept a `user` and filter profiles.

```python
    def get_stream(self, user=None): # Update signature to accept user
        redis_client = RedisClient.get_client()
        # ... existing checks ...

        # 1. Check existing active stream
        stream_id_bytes = redis_client.get(f"channel_stream:{self.id}")
        if stream_id_bytes:
            # ... logic to check if profile is in user.m3u_profiles ...
            # If not allowed, don't return, fall through to re-assign

        # 2. Assignment Logic
        allowed_profile_ids = None
        if user and user.m3u_profiles.exists():
            allowed_profile_ids = set(user.m3u_profiles.values_list('id', flat=True))

        for stream in self.streams.all().order_by("channelstream__order"):
            m3u_profiles = m3u_account.profiles.filter(is_active=True)
            
            # FILTER HERE:
            if allowed_profile_ids is not None:
                m3u_profiles = m3u_profiles.filter(id__in=allowed_profile_ids)
            
            # ... proceed with connection check and assignment ...
```

## 4. URL Generation & Proxy Updates
**File:** `apps/proxy/ts_proxy/url_utils.py`

Update `generate_stream_url` to pass the user object.

```python
def generate_stream_url(channel_id: str, user: Optional['User'] = None) -> Tuple[str, str, bool, Optional[int]]:
    # ...
    # Ensure user is passed to get_stream:
    stream_id, profile_id, error_reason = channel.get_stream(user=user)
    # ...
```

**File:** `apps/proxy/ts_proxy/views.py`

Update endpoints to identifying users.

```python
@api_view(["GET"])
def stream_ts(request, channel_id, user_id=None): # Add user_id
    # ... load user from user_id ...
    # ... check if current active channel profile is allowed for user ...
    # ... if not, force re-initialization ...
    # ... pass user to generate_stream_url(channel_id, user=user) ...

@api_view(["GET"])
def stream_xc(request, username, password, channel_id):
    # ... authenticate user ...
    return stream_ts(request._request, str(channel.uuid), user_id=user.id) # Pass user ID
```

## 5. API Routing for UI Support
**File:** `apps/m3u/api_urls.py` & `apps/m3u/api_views.py`

Add a flat list endpoint for all profiles.

```python
# api_urls.py
router.register(r"profiles", M3UAccountProfileViewSet, basename="m3u-profiles")

# api_views.py
class M3UAccountProfileViewSet(viewsets.ModelViewSet):
    @action(detail=False, methods=['get'], url_path='all')
    def list_all(self, request):
        # returns all M3UAccountProfile objects
```

## 6. Frontend UI Changes
**File:** `frontend/src/api.js`
Add `getM3UProfilesAll()` method.

**File:** `frontend/src/components/forms/User.jsx`
Add `MultiSelect` component for `m3u_profiles` populated via the new API.

**File:** `frontend/src/components/tables/UsersTable.jsx`
Add a column to display the count of assigned M3U profiles.

## 7. Migration Commands
After applying code changes, run:
```bash
python manage.py makemigrations accounts
python manage.py migrate
```
