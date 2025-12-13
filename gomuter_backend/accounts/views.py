from rest_framework import generics, permissions
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from django.conf import settings
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import send_mail
from django.db.models import Q
from django.utils.encoding import force_bytes
from django.utils.http import urlsafe_base64_decode, urlsafe_base64_encode
import logging

from .models import User
from .serializers import (
    RegisterSerializer,
    UserMeSerializer,
    PasswordResetRequestSerializer,
    PasswordResetConfirmSerializer,
)

logger = logging.getLogger(__name__)

class RegisterView(generics.CreateAPIView):
    queryset = User.objects.all()
    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]

class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = UserMeSerializer(request.user)
        return Response(serializer.data)


class PasswordResetRequestView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        identifier = serializer.validated_data['identifier'].strip()
        user = (
            User.objects.filter(Q(email__iexact=identifier) | Q(username__iexact=identifier))
            .order_by('id')
            .first()
        )

        # Always return a generic message to avoid user enumeration.
        detail = (
            'Jika akun ditemukan, instruksi reset password akan dikirim ke email Anda.'
        )

        if user and user.email:
            uid = urlsafe_base64_encode(force_bytes(user.pk))
            token = default_token_generator.make_token(user)

            subject = 'Reset Password GoMuter'
            body = (
                'Anda meminta reset password.\n\n'
                f'UID: {uid}\n'
                f'TOKEN: {token}\n\n'
                'Masukkan UID dan TOKEN tersebut di aplikasi untuk membuat password baru.\n'
                'Jika Anda tidak merasa meminta reset password, abaikan email ini.'
            )

            from_email = getattr(settings, 'DEFAULT_FROM_EMAIL', None) or 'no-reply@gomuter.local'

            try:
                send_mail(subject, body, from_email, [user.email], fail_silently=False)
            except Exception:
                # Keep response generic to avoid user enumeration, but log details for debugging.
                logger.exception('Password reset email send failed')

        return Response({'detail': detail})


class PasswordResetConfirmView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        uid = serializer.validated_data['uid']
        token = serializer.validated_data['token']
        new_password = serializer.validated_data['new_password']

        try:
            user_id = urlsafe_base64_decode(uid).decode()
            user = User.objects.get(pk=user_id)
        except Exception:
            return Response({'detail': 'Token reset tidak valid.'}, status=400)

        if not default_token_generator.check_token(user, token):
            return Response({'detail': 'Token reset tidak valid atau sudah kadaluarsa.'}, status=400)

        user.set_password(new_password)
        user.save(update_fields=['password'])
        return Response({'detail': 'Password berhasil diperbarui. Silakan login kembali.'})