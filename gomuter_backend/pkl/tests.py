from django.contrib.auth import get_user_model
from django.test import override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import PKL, LokasiPKL, PKLProduct


User = get_user_model()


@override_settings(SECURE_SSL_REDIRECT=False)
class BuyerOnlyAccessTests(APITestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(
            username='buyer',
            email='buyer@example.com',
            password='password123',
            role='USER',
        )
        self.pkl_user = User.objects.create_user(
            username='pkluser',
            email='pkl@example.com',
            password='password123',
            role='PKL',
        )
        self.target_user = User.objects.create_user(
            username='targetpkl',
            email='target@example.com',
            password='password123',
            role='PKL',
        )
        self.target_pkl = PKL.objects.create(
            user=self.target_user,
            nama_usaha='Siomay Mantap',
            jenis_dagangan='Makanan',
            jam_operasional='08.00-17.00',
            status_aktif=True,
            status_verifikasi='DITERIMA',
        )
        self.product = PKLProduct.objects.create(
            pkl=self.target_pkl,
            name='Siomay',
            price=10000,
            is_available=True,
        )

    def test_pkl_cannot_create_preorder(self):
        self.client.force_authenticate(user=self.pkl_user)

        response = self.client.post(
            reverse('preorder-create'),
            {
                'pkl_id': self.target_pkl.id,
                'items': [{'product_id': self.product.id, 'quantity': 1}],
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_buyer_can_create_preorder(self):
        self.client.force_authenticate(user=self.buyer)

        response = self.client.post(
            reverse('preorder-create'),
            {
                'pkl_id': self.target_pkl.id,
                'items': [{'product_id': self.product.id, 'quantity': 2}],
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['pembeli'], self.buyer.id)

    def test_pkl_cannot_start_chat(self):
        self.client.force_authenticate(user=self.pkl_user)

        response = self.client.post(
            reverse('chat-start'),
            {'pkl_id': self.target_pkl.id},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_buyer_can_start_chat(self):
        self.client.force_authenticate(user=self.buyer)

        response = self.client.post(
            reverse('chat-start'),
            {'pkl_id': self.target_pkl.id},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['pembeli'], self.buyer.id)


@override_settings(SECURE_SSL_REDIRECT=False)
class PKLVerificationGateTests(APITestCase):
    def setUp(self):
        self.pkl_user = User.objects.create_user(
            username='pendingpkl',
            email='pending@example.com',
            password='password123',
            role='PKL',
        )
        self.pkl = PKL.objects.create(
            user=self.pkl_user,
            nama_usaha='Bakso Tunggu',
            jenis_dagangan='Makanan',
            jam_operasional='08.00-17.00',
            status_aktif=False,
            status_verifikasi='PENDING',
        )

    def test_pending_pkl_cannot_activate_store(self):
        self.client.force_authenticate(user=self.pkl_user)

        response = self.client.put(
            reverse('pkl-profile'),
            {'status_aktif': True},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.pkl.refresh_from_db()
        self.assertFalse(self.pkl.status_aktif)

    def test_pending_pkl_cannot_update_location(self):
        self.client.force_authenticate(user=self.pkl_user)

        response = self.client.post(
            reverse('pkl-update-location'),
            {'latitude': -6.9, 'longitude': 107.6},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(LokasiPKL.objects.filter(pkl=self.pkl).count(), 0)

    def test_pkl_cannot_self_verify_profile(self):
        self.client.force_authenticate(user=self.pkl_user)

        response = self.client.put(
            reverse('pkl-profile'),
            {'status_verifikasi': 'DITERIMA'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.pkl.refresh_from_db()
        self.assertEqual(self.pkl.status_verifikasi, 'PENDING')

    def test_verified_pkl_can_activate_and_update_location(self):
        self.pkl.status_verifikasi = 'DITERIMA'
        self.pkl.save(update_fields=['status_verifikasi'])
        self.client.force_authenticate(user=self.pkl_user)

        activate_response = self.client.put(
            reverse('pkl-profile'),
            {'status_aktif': True},
            format='json',
        )
        location_response = self.client.post(
            reverse('pkl-update-location'),
            {'latitude': -6.9, 'longitude': 107.6},
            format='json',
        )

        self.assertEqual(activate_response.status_code, status.HTTP_200_OK)
        self.assertEqual(location_response.status_code, status.HTTP_201_CREATED)
        self.pkl.refresh_from_db()
        self.assertTrue(self.pkl.status_aktif)
