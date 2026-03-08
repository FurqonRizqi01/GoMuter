import os

from django.core.management.base import BaseCommand

from accounts.models import User


class Command(BaseCommand):
    help = "Ensure a production admin user exists and has required flags"

    def handle(self, *args, **options):
        username = os.getenv("BOOTSTRAP_ADMIN_USERNAME", "").strip()
        password = os.getenv("BOOTSTRAP_ADMIN_PASSWORD", "").strip()
        email = os.getenv("BOOTSTRAP_ADMIN_EMAIL", "admin@gomuter.local").strip()

        # Skip safely when env vars are not configured.
        if not username or not password:
            self.stdout.write(self.style.WARNING("ensure_admin skipped: BOOTSTRAP_ADMIN_* not set"))
            return

        user, created = User.objects.get_or_create(
            username=username,
            defaults={
                "email": email,
                "role": "ADMIN",
                "is_staff": True,
                "is_superuser": True,
                "is_active": True,
            },
        )

        changed = False

        if user.email != email:
            user.email = email
            changed = True

        if user.role != "ADMIN":
            user.role = "ADMIN"
            changed = True

        if not user.is_staff:
            user.is_staff = True
            changed = True

        if not user.is_superuser:
            user.is_superuser = True
            changed = True

        if not user.is_active:
            user.is_active = True
            changed = True

        # Always reset to configured value on deploy for recovery consistency.
        user.set_password(password)
        changed = True

        if changed:
            user.save()

        if created:
            self.stdout.write(self.style.SUCCESS(f"ensure_admin created user '{username}'"))
        else:
            self.stdout.write(self.style.SUCCESS(f"ensure_admin updated user '{username}'"))
