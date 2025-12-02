from django.urls import path

from .views import (
    PKLProfileView,
    PKLUpdateLocationView,
    PKLTodayStatsView,
    BuyerLocationView,
    ActivePKLListView,
    FavoritePKLListCreateView,
    FavoritePKLDeleteView,
    PKLDetailView,
    AdminPKLPendingListView,
    AdminPKLVerifyView,
    AdminMonitoringPKLView,
    CreatePreOrderView,
    MyPreOrderListView,
    PKLPreOrderListView,
    UpdatePreOrderStatusView,
    SubmitDPProofView,
    PKLDPVerificationView,
    DPProofUploadView,
    NotificationListView,
    NotificationMarkReadView,
)
from .views_chat import ChatListView, StartChatView, ChatMessagesView

urlpatterns = [
    # PKL owner endpoints
    path('profile/', PKLProfileView.as_view(), name='pkl-profile'),
    path('update-location/', PKLUpdateLocationView.as_view(), name='pkl-update-location'),
    path('stats/today/', PKLTodayStatsView.as_view(), name='pkl-stats-today'),
    path('buyer/location/', BuyerLocationView.as_view(), name='buyer-location'),
    path('buyer/favorites/', FavoritePKLListCreateView.as_view(), name='buyer-favorite-list-create'),
    path('buyer/favorites/<int:pkl_id>/', FavoritePKLDeleteView.as_view(), name='buyer-favorite-delete'),
    path('buyer/notifications/', NotificationListView.as_view(), name='buyer-notification-list'),
    path('buyer/notifications/<int:notification_id>/read/', NotificationMarkReadView.as_view(), name='buyer-notification-read'),

    # public/pembeli endpoints
    path('active/', ActivePKLListView.as_view(), name='pkl-active-list'),
    path('<int:pk>/', PKLDetailView.as_view(), name='pkl-detail'),

    # admin endpoints
    path('admin/pending/', AdminPKLPendingListView.as_view(), name='admin-pkl-pending'),
    path('admin/<int:pk>/verify/', AdminPKLVerifyView.as_view(), name='admin-pkl-verify'),
    path('admin/monitor/', AdminMonitoringPKLView.as_view(), name='admin-pkl-monitor'),

    # chat endpoints
    path('chat/', ChatListView.as_view(), name='chat-list'),
    path('chat/start/', StartChatView.as_view(), name='chat-start'),
    path('chat/<int:chat_id>/messages/', ChatMessagesView.as_view(), name='chat-messages'),

    # preorder endpoints
    path('preorder/create/', CreatePreOrderView.as_view(), name='preorder-create'),
    path('preorder/my/', MyPreOrderListView.as_view(), name='preorder-my'),
    path('preorder/pkl/', PKLPreOrderListView.as_view(), name='preorder-pkl'),
    path('preorder/<int:preorder_id>/status/', UpdatePreOrderStatusView.as_view(), name='preorder-update-status'),
    path('preorder/<int:preorder_id>/upload-dp/', SubmitDPProofView.as_view(), name='preorder-upload-dp'),
    path('preorder/<int:preorder_id>/dp-verification/', PKLDPVerificationView.as_view(), name='preorder-dp-verification'),
    path('upload/dp-proof/', DPProofUploadView.as_view(), name='upload-dp-proof'),
]
