from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from .models import LokasiPKL, PKL, PKLProduct


User = get_user_model()


@override_settings(SECURE_SSL_REDIRECT=False)
class CoreAPIBlackBoxTests(APITestCase):
    password = 'password123'

    def setUp(self):
        self.buyer = User.objects.create_user(
            username='bb_buyer',
            email='bb_buyer@example.com',
            password=self.password,
            role='USER',
        )
        self.pkl_user = User.objects.create_user(
            username='bb_pkl',
            email='bb_pkl@example.com',
            password=self.password,
            role='PKL',
        )
        self.pending_pkl_user = User.objects.create_user(
            username='bb_pending_pkl',
            email='bb_pending_pkl@example.com',
            password=self.password,
            role='PKL',
        )
        self.admin = User.objects.create_user(
            username='bb_admin',
            email='bb_admin@example.com',
            password=self.password,
            role='ADMIN',
            is_staff=True,
        )

        self.pkl = PKL.objects.create(
            user=self.pkl_user,
            nama_usaha='Siomay Black Box',
            jenis_dagangan='Makanan',
            jam_operasional='08:00 - 17:00',
            status_aktif=True,
            status_verifikasi='DITERIMA',
        )
        self.pending_pkl = PKL.objects.create(
            user=self.pending_pkl_user,
            nama_usaha='Bakso Pending',
            jenis_dagangan='Makanan',
            jam_operasional='09:00 - 18:00',
            status_aktif=False,
            status_verifikasi='PENDING',
        )
        self.product = PKLProduct.objects.create(
            pkl=self.pkl,
            name='Siomay Komplit',
            price=15000,
            description='Siomay untuk pengujian.',
            is_available=True,
            is_featured=True,
        )
        LokasiPKL.objects.create(
            pkl=self.pkl,
            latitude=-6.424076,
            longitude=106.758254,
            status='AKTIF',
        )

        self.buyer_token = self._token_for('bb_buyer')
        self.pkl_token = self._token_for('bb_pkl')
        self.pending_pkl_token = self._token_for('bb_pending_pkl')
        self.admin_token = self._token_for('bb_admin')

    def _token_for(self, username):
        response = self.client.post(
            '/api/auth/token/',
            {'username': username, 'password': self.password},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data['access']

    def _authorize(self, token):
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

    def _create_preorder(self):
        self._authorize(self.buyer_token)
        response = self.client.post(
            '/api/pkl/preorder/create/',
            {
                'pkl_id': self.pkl.id,
                'items': [{'product_id': self.product.id, 'quantity': 2}],
                'pickup_address': 'Jl. UAT No. 1',
                'pickup_latitude': -6.424100,
                'pickup_longitude': 106.758200,
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        return response

    def test_01_registration_success(self):
        response = self.client.post(
            '/api/accounts/register/',
            {
                'username': 'bb_new_buyer',
                'email': 'bb_new_buyer@example.com',
                'password': self.password,
                'role': 'USER',
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(User.objects.filter(username='bb_new_buyer').exists())

    def test_02_login_success(self):
        response = self.client.post(
            '/api/auth/token/',
            {'username': 'bb_buyer', 'password': self.password},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        for key in ('access', 'refresh', 'role', 'username', 'user_id'):
            self.assertIn(key, response.data)

    def test_03_login_failed(self):
        response = self.client.post(
            '/api/auth/token/',
            {'username': 'bb_buyer', 'password': 'wrong-password'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_04_get_own_profile(self):
        self._authorize(self.buyer_token)
        response = self.client.get('/api/accounts/me/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['username'], 'bb_buyer')

    def test_05_create_update_pkl_profile_and_read_only_verification(self):
        new_pkl_user = User.objects.create_user(
            username='bb_profile_pkl',
            email='bb_profile_pkl@example.com',
            password=self.password,
            role='PKL',
        )
        token = self._token_for(new_pkl_user.username)
        self._authorize(token)

        create_response = self.client.post(
            '/api/pkl/profile/',
            {
                'nama_usaha': 'Warung Profil',
                'jenis_dagangan': 'Makanan',
                'jam_operasional': '08:00 - 16:00',
                'status_verifikasi': 'DITERIMA',
                'catatan_verifikasi': 'Tidak boleh diisi PKL',
            },
            format='json',
        )
        self.assertEqual(create_response.status_code, status.HTTP_201_CREATED)
        profile = PKL.objects.get(user=new_pkl_user)
        self.assertEqual(profile.status_verifikasi, 'PENDING')
        self.assertFalse(profile.catatan_verifikasi)

        update_response = self.client.put(
            '/api/pkl/profile/',
            {
                'nama_usaha': 'Warung Profil Diperbarui',
                'status_verifikasi': 'DITERIMA',
                'catatan_verifikasi': 'Tetap tidak boleh diisi PKL',
            },
            format='json',
        )
        self.assertEqual(update_response.status_code, status.HTTP_200_OK)
        profile.refresh_from_db()
        self.assertEqual(profile.nama_usaha, 'Warung Profil Diperbarui')
        self.assertEqual(profile.status_verifikasi, 'PENDING')
        self.assertFalse(profile.catatan_verifikasi)

    def test_06_verified_pkl_updates_location(self):
        self._authorize(self.pkl_token)
        response = self.client.post(
            '/api/pkl/update-location/',
            {'latitude': -6.425000, 'longitude': 106.759000},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(LokasiPKL.objects.filter(pkl=self.pkl).count(), 2)

    def test_07_pending_pkl_cannot_update_location(self):
        self._authorize(self.pending_pkl_token)
        response = self.client.post(
            '/api/pkl/update-location/',
            {'latitude': -6.425000, 'longitude': 106.759000},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(LokasiPKL.objects.filter(pkl=self.pending_pkl).exists())

    def test_08_save_buyer_location(self):
        self._authorize(self.buyer_token)
        response = self.client.post(
            '/api/pkl/buyer/location/',
            {'latitude': -6.424100, 'longitude': 106.758200, 'radius_m': 300},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['radius_m'], 300)

    def test_09_get_filtered_active_pkls(self):
        response = self.client.get('/api/pkl/active/?jenis=Makanan&q=siomay')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(any(item['id'] == self.pkl.id for item in response.data))
        self.assertFalse(any(item['id'] == self.pending_pkl.id for item in response.data))

    def test_10_get_pkl_detail(self):
        response = self.client.get(f'/api/pkl/{self.pkl.id}/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['id'], self.pkl.id)
        self.assertEqual(response.data['products'][0]['name'], 'Siomay Komplit')

    def test_11_manage_favorite_pkl(self):
        self._authorize(self.buyer_token)
        create_response = self.client.post(
            '/api/pkl/buyer/favorites/',
            {'pkl_id': self.pkl.id},
            format='json',
        )
        self.assertEqual(create_response.status_code, status.HTTP_201_CREATED)
        delete_response = self.client.delete(f'/api/pkl/buyer/favorites/{self.pkl.id}/')
        self.assertEqual(delete_response.status_code, status.HTTP_204_NO_CONTENT)

    def test_12_create_preorder_with_total_and_dp(self):
        response = self._create_preorder()
        self.assertEqual(response.data['total_price'], 30000)
        self.assertEqual(response.data['dp_amount'], 6000)
        self.assertEqual(response.data['status'], 'PENDING')

    def test_13_get_buyer_and_pkl_preorder_lists(self):
        preorder = self._create_preorder().data
        self._authorize(self.buyer_token)
        buyer_response = self.client.get('/api/pkl/preorder/my/')
        self.assertEqual(buyer_response.status_code, status.HTTP_200_OK)
        self.assertTrue(any(item['id'] == preorder['id'] for item in buyer_response.data))

        self._authorize(self.pkl_token)
        pkl_response = self.client.get('/api/pkl/preorder/pkl/')
        self.assertEqual(pkl_response.status_code, status.HTTP_200_OK)
        self.assertTrue(any(item['id'] == preorder['id'] for item in pkl_response.data))

    def test_14_pkl_updates_preorder_status(self):
        preorder = self._create_preorder().data
        self._authorize(self.pkl_token)
        response = self.client.post(
            f"/api/pkl/preorder/{preorder['id']}/status/",
            {'status': 'DITERIMA'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], 'DITERIMA')

    def test_15_submit_and_verify_dp(self):
        preorder = self._create_preorder().data
        self._authorize(self.buyer_token)
        submit_response = self.client.post(
            f"/api/pkl/preorder/{preorder['id']}/upload-dp/",
            {'bukti_dp_url': 'https://example.com/dp-proof.jpg'},
            format='json',
        )
        self.assertEqual(submit_response.status_code, status.HTTP_200_OK)
        self.assertEqual(submit_response.data['dp_status'], 'MENUNGGU_KONFIRMASI')

        self._authorize(self.pkl_token)
        verify_response = self.client.post(
            f"/api/pkl/preorder/{preorder['id']}/dp-verification/",
            {'action': 'TERIMA'},
            format='json',
        )
        self.assertEqual(verify_response.status_code, status.HTTP_200_OK)
        self.assertEqual(verify_response.data['dp_status'], 'TERKONFIRMASI')
        self.assertEqual(verify_response.data['status'], 'DITERIMA')

    def test_16_start_chat_and_send_message(self):
        self._authorize(self.buyer_token)
        start_response = self.client.post(
            '/api/pkl/chat/start/',
            {'pkl_id': self.pkl.id},
            format='json',
        )
        self.assertEqual(start_response.status_code, status.HTTP_200_OK)

        chat_id = start_response.data['id']
        message_response = self.client.post(
            f'/api/pkl/chat/{chat_id}/messages/',
            {'content': 'Pesan pengujian black box.'},
            format='json',
        )
        self.assertEqual(message_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(message_response.data['content'], 'Pesan pengujian black box.')

    def test_17_get_and_mark_notification_read(self):
        self._authorize(self.buyer_token)
        save_location_response = self.client.post(
            '/api/pkl/buyer/location/',
            {'latitude': -6.424100, 'longitude': 106.758200, 'radius_m': 300},
            format='json',
        )
        self.assertEqual(save_location_response.status_code, status.HTTP_201_CREATED)

        list_response = self.client.get('/api/pkl/buyer/notifications/')
        self.assertEqual(list_response.status_code, status.HTTP_200_OK)
        self.assertGreater(len(list_response.data), 0)

        notification_id = list_response.data[0]['id']
        read_response = self.client.post(
            f'/api/pkl/buyer/notifications/{notification_id}/read/',
            format='json',
        )
        self.assertEqual(read_response.status_code, status.HTTP_200_OK)
        self.assertTrue(read_response.data['is_read'])

    def test_18_admin_dashboard(self):
        self._authorize(self.admin_token)
        response = self.client.get('/api/pkl/admin/dashboard/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('summary', response.data)
        self.assertIn('trend', response.data)

    def test_private_endpoint_rejects_missing_token(self):
        self.client.credentials()
        response = self.client.get('/api/accounts/me/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_admin_endpoint_rejects_non_admin(self):
        self._authorize(self.buyer_token)
        response = self.client.get('/api/pkl/admin/dashboard/')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

