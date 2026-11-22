# User guide

This guide is for the person who uses Nextcloud. Your administrator gives you the address of
the server, for example `https://cloud.example.org`, and your account.

## Log in

Open the address in a browser. Log in with your company account, the same one as for your
mail or your computer:

- with Active Directory: your login (`john`) or `john@ad.example.org`
- with OpenLDAP: your login or your mail address

Your administrator may also have given you a local Nextcloud account, with its own password.

To change your password, ask your administrator: company passwords are not changed in
Nextcloud. A local account changes its password in **Personal settings > Security**.

## Desktop client

The desktop client keeps a folder of your computer in sync with Nextcloud.

1. Download it from [nextcloud.com/install](https://nextcloud.com/install/#install-clients)
   and install it.
2. Choose **Log in to your Nextcloud** and type the server address.
3. The browser opens. Log in and allow the access.
4. Choose the local folder and what to sync.

For a large account, choose **Virtual files** where the client offers it. Files then appear
in the folder but download only when you open them.

## Mobile app

Install **Nextcloud** from the App Store or Google Play. Type the server address, log in in
the page that opens, and allow the access. The app can upload your photos by itself: turn on
**Auto upload** in its settings.

## Calendar, contacts and mail apps

When your administrator has installed the **Calendar** and **Contacts** apps, Nextcloud
shares them with CalDAV and CardDAV. Open **Calendar** or **Contacts** in the web page, then
the settings at the bottom left, to copy the address of a calendar. Most apps only need the
server address and your account.

When two-factor authentication is on, these apps cannot ask for the code. Create an app
password in **Personal settings > Security > Devices & sessions** and use it instead of your
password.

## Two-factor authentication

A second factor protects your account when your password leaks. You need an authenticator
app on your phone, such as FreeOTP, Aegis or Google Authenticator.

1. Open **Personal settings > Security**.
2. Check **Enable TOTP**.
3. Scan the QR code with the app.
4. Type the 6-digit code the app shows, then **Verify**.
5. Generate the **backup codes** and keep them in a safe place. Each code lets you log in
   once without the phone.

Your administrator may force it: Nextcloud then asks you to set it up right after your
password, at the next login.

If you lose your phone, log in with a backup code and set up TOTP again. Without backup
codes, ask your administrator to reset it.

## Share a file

Click the share icon next to a file or a folder. Type the name of a colleague to share it
inside the company, or create a public link for someone outside. A public link can have a
password and an expiry date: use both for anything private.

## Restore a file

Deleted files go to **Deleted files** at the bottom left of the Files page. Restore them from
there. A file you changed keeps its old versions: open its details, then the **Versions** tab.
