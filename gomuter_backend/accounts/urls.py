from django.urls import path
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
)
from .views import (
    RegisterView,
    MeView,
    PasswordResetRequestView,
    PasswordResetConfirmView,
)

urlpatterns = [
    # register user baru (pembeli / PKL)
    path('register/', RegisterView.as_view(), name='register'),

    # login → dapatkan access & refresh token
    path('token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    # refresh access token
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    # info user yang sedang login
    path('me/', MeView.as_view(), name='accounts-me'),

    # forgot password
    path(
        'password-reset/request/',
        PasswordResetRequestView.as_view(),
        name='password_reset_request',
    ),
    path(
        'password-reset/confirm/',
        PasswordResetConfirmView.as_view(),
        name='password_reset_confirm',
    ),
]
