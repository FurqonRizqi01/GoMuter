from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Chat, ChatMessage, PKL
from .serializers import ChatSerializer, ChatMessageSerializer


class ChatListView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        role = getattr(request.user, "role", "").upper()
        if role == "PKL":
            chats = Chat.objects.filter(pkl__user=request.user)
        else:
            chats = Chat.objects.filter(pembeli=request.user)

        serializer = ChatSerializer(chats.order_by("-updated_at"), many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


class StartChatView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        pkl_id = request.data.get('pkl_id')
        if not pkl_id:
            return Response(
                {"detail": "pkl_id wajib diisi."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        pkl = get_object_or_404(PKL, id=pkl_id)
        chat, _ = Chat.objects.get_or_create(
            pembeli=request.user,
            pkl=pkl,
        )

        serializer = ChatSerializer(chat)
        return Response(serializer.data, status=status.HTTP_200_OK)


class ChatMessagesView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, chat_id):
        chat = get_object_or_404(Chat, id=chat_id)
        if chat.pembeli != request.user and chat.pkl.user != request.user:
            return Response(
                {"detail": "Tidak punya akses ke chat ini."},
                status=status.HTTP_403_FORBIDDEN,
            )

        messages = chat.messages.all()
        serializer = ChatMessageSerializer(messages, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def post(self, request, chat_id):
        chat = get_object_or_404(Chat, id=chat_id)
        if chat.pembeli != request.user and chat.pkl.user != request.user:
            return Response(
                {"detail": "Tidak punya akses ke chat ini."},
                status=status.HTTP_403_FORBIDDEN,
            )

        content = request.data.get('content')
        if not content:
            return Response(
                {"detail": "content tidak boleh kosong."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        message = ChatMessage.objects.create(
            chat=chat,
            sender=request.user,
            content=content,
        )

        serializer = ChatMessageSerializer(message)
        chat.save(update_fields=["updated_at"])
        return Response(serializer.data, status=status.HTTP_201_CREATED)
