# Vashudha Authentication System — Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Database Setup](#database-setup)
4. [Backend Endpoints](#backend-endpoints)
   - [POST /api/auth/register](#post-apiauthregister)
   - [POST /api/auth/login](#post-apiauthlogin)
   - [GET /api/auth/profile](#get-apiauthprofile)
   - [PATCH /api/auth/profile](#patch-apiauthprofile)
   - [POST /api/auth/wallet](#post-apiauthwallet)
   - [POST /api/auth/change-password](#post-apiauthchange-password)
   - [POST /api/auth/logout](#post-apiauthlogout)
5. [Authentication Flow](#authentication-flow)
6. [Frontend Integration](#frontend-integration)
7. [Error Reference](#error-reference)
8. [Environment Variables](#environment-variables)

---

## Overview

Vashudha uses **JWT (JSON Web Tokens)** for stateless authentication. Passwords are hashed with **bcrypt**. All user records are stored in a single `users` table in Supabase. On register/login the backend returns a signed JWT that the frontend stores in `localStorage` and attaches to every request via the `Authorization: Bearer <token>` header.

Three user roles are supported:

| Role        | Description                                           | Redirected to   |
|-------------|-------------------------------------------------------|-----------------|
| `donor`     | Restaurants, caterers, hostels, PGs, individuals      | `/donate`       |
| `ngo`       | NGO volunteers and organizations                      | `/ngo`          |
| `corporate` | Companies buying carbon credits for ESG compliance    | `/marketplace`  |

---

## Architecture

```
Frontend (Next.js)                    Backend (Flask)
────────────────────                  ──────────────────────────────────────
useAuth.tsx  ──── POST /api/auth/register ──►  routes/auth.py
             ──── POST /api/auth/login    ──►    │
             ──── GET  /api/auth/profile  ──►    ▼
             ◄─── { token, user }             services/supabase_client.py
                                                │
                                                ▼
             localStorage (token + user)    Supabase `users` table
```

**Token lifecycle:**
- Issued on register and login
- Valid for **72 hours** (configurable via `JWT_EXPIRY_HOURS`)
- Stored client-side in `localStorage` under key `vashudha_token`
- Sent as `Authorization: Bearer <token>` on every authenticated request
- Stateless — logout just clears localStorage; no server-side revocation

---

## Database Setup

Run the migration in **Supabase SQL Editor** before starting the backend:

```
migrations/001_create_users_table.sql
```

This creates the `users` table with all role-specific columns and indexes.

> **Note:** The backend also mirrors new registrations into the existing `donors` and `ngos` legacy tables so that all existing listing/rescue routes continue to work without modification.

---

## Backend Endpoints

Base URL: `http://localhost:5000` (dev) or your production domain.

All auth endpoints are under `/api/auth/`.

---

### POST /api/auth/register

Create a new account.

#### Donor body
```json
{
  "role":         "donor",
  "donorType":    "restaurant",
  "name":         "Priya Sharma",
  "email":        "priya@hotelxyz.com",
  "phone":        "+91-9876543210",
  "password":     "secret123",
  "businessName": "Hotel XYZ",
  "address":      "MI Road, Jaipur",
  "city":         "Jaipur",
  "state":        "Rajasthan",
  "pincode":      "302001",
  "gstNumber":    "08AABCU9603R1ZM",
  "fssaiLicense": "12726001000123"
}
```

#### NGO body
```json
{
  "role":               "ngo",
  "ngoName":            "Aashray Foundation",
  "name":               "Rajesh Kumar",
  "email":              "rajesh@aashray.org",
  "phone":              "+91-9800000001",
  "password":           "secret123",
  "address":            "Adarsh Nagar, Jaipur",
  "city":               "Jaipur",
  "state":              "Rajasthan",
  "pincode":            "302004",
  "darpanId":           "RJ/2025/123456",
  "registrationNumber": "SOC/RJ/2020/456",
  "panNumber":          "AAATA1234F",
  "operatingAreas":     "Jaipur, Jodhpur, Udaipur"
}
```

#### Corporate body
```json
{
  "role":           "corporate",
  "companyName":    "Tata Consultancy",
  "name":           "Ananya Desai",
  "designation":    "ESG Head",
  "email":          "ananya@tcs.com",
  "phone":          "+91-9876543212",
  "password":       "secret123",
  "address":        "MG Road, Mumbai",
  "city":           "Mumbai",
  "state":          "Maharashtra",
  "pincode":        "400001",
  "gstNumber":      "27AABCT1234F1ZP",
  "cin":            "L22210MH1995PLC084781",
  "companyPan":     "AABCT1234F",
  "companyWebsite": "https://tcs.com"
}
```

#### Response `201`
```json
{
  "message": "Account created successfully",
  "token":   "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id":          "a1b2c3d4-...",
    "role":        "donor",
    "email":       "priya@hotelxyz.com",
    "name":        "Priya Sharma",
    "verified":    false,
    "created_at":  "2026-03-08T10:00:00Z",
    ...
  }
}
```

#### Error responses
| Status | Condition |
|--------|-----------|
| `400`  | Missing required fields, password too short, invalid role |
| `409`  | Email already registered |
| `500`  | Database insert failed |

---

### POST /api/auth/login

Authenticate with email + password.

#### Body
```json
{
  "email":    "priya@hotelxyz.com",
  "password": "secret123"
}
```

#### Response `200`
```json
{
  "message": "Login successful",
  "token":   "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": { ... }
}
```

#### Error responses
| Status | Condition |
|--------|-----------|
| `400`  | email or password missing |
| `401`  | Wrong credentials |

---

### GET /api/auth/profile

Fetch the authenticated user's full profile.

#### Headers
```
Authorization: Bearer <token>
```

#### Response `200`
```json
{
  "id":          "a1b2c3d4-...",
  "role":        "donor",
  "email":       "priya@hotelxyz.com",
  "name":        "Priya Sharma",
  "phone":       "+91-9876543210",
  "city":        "Jaipur",
  "verified":    true,
  "hgc_balance": 12.5,
  ...
}
```

#### Error responses
| Status | Condition |
|--------|-----------|
| `401`  | Missing or invalid token |
| `404`  | User not found (deleted) |

---

### PATCH /api/auth/profile

Update the authenticated user's profile.

#### Headers
```
Authorization: Bearer <token>
```

#### Body (all fields optional)
```json
{
  "name":         "Priya S.",
  "phone":        "+91-9999999999",
  "city":         "Delhi",
  "walletAddress":"0xABCDEF..."
}
```

All accepted fields:
`name`, `phone`, `address`, `city`, `state`, `pincode`, `walletAddress`, `businessName`, `gstNumber`, `fssaiLicense`, `ngoName`, `darpanId`, `operatingAreas`, `companyName`, `designation`, `cin`, `companyPan`, `companyWebsite`

#### Response `200`
```json
{
  "message": "Profile updated",
  "user":    { ... }
}
```

---

### POST /api/auth/wallet

Save a MetaMask wallet address to the user's profile.

#### Headers
```
Authorization: Bearer <token>
```

#### Body
```json
{ "walletAddress": "0xAbCdEf1234567890..." }
```

#### Response `200`
```json
{ "message": "Wallet address saved", "walletAddress": "0xAbCdEf..." }
```

---

### POST /api/auth/change-password

Change the authenticated user's password.

#### Headers
```
Authorization: Bearer <token>
```

#### Body
```json
{
  "currentPassword": "oldpass123",
  "newPassword":     "newpass456"
}
```

#### Response `200`
```json
{ "message": "Password changed successfully" }
```

#### Error responses
| Status | Condition |
|--------|-----------|
| `401`  | Current password incorrect |
| `400`  | New password too short |

---

### POST /api/auth/logout

Client-side logout hint. The client should discard the token from `localStorage`.

#### Response `200`
```json
{ "message": "Logged out. Please discard your token." }
```

> JWT is stateless — no server-side session to destroy. Simply removing the token from localStorage is sufficient.

---

## Authentication Flow

### Registration
```
User fills form → POST /api/auth/register
  → Backend validates fields
  → Checks email uniqueness in Supabase
  → Hashes password with bcrypt
  → Inserts into `users` table
  → Mirrors into `donors`/`ngos` table (backward compat)
  → Signs JWT (72h expiry)
  → Returns { token, user }
Frontend:
  → Stores token in localStorage ("vashudha_token")
  → Stores user in localStorage ("vashudha_auth")
  → Redirects to role dashboard
```

### Login
```
User submits email+password → POST /api/auth/login
  → Backend looks up user by email
  → bcrypt.checkpw(plain, hash)
  → Updates last_login_at
  → Signs JWT
  → Returns { token, user }
Frontend:
  → Same as above
```

### Authenticated Request
```
Any protected page calls useAuth() → user + token from context
API call → axios interceptor adds "Authorization: Bearer <token>"
Backend middleware.require_auth → jwt.decode(token, JWT_SECRET)
  → Sets g.current_user = { id, role, email }
Route handler proceeds
```

---

## Frontend Integration

### `useAuth` hook

```tsx
import { useAuth } from "@/hooks/useAuth";

const { user, token, isAuthenticated, isLoading, login, register, logout,
        updateProfile, saveWalletAddress } = useAuth();
```

| Property / Method | Type | Description |
|---|---|---|
| `user` | `VashudhaUser \| null` | Current user object |
| `token` | `string \| null` | Raw JWT string |
| `isAuthenticated` | `boolean` | `true` if user + token present |
| `isLoading` | `boolean` | `true` during API calls |
| `login(data)` | `Promise<void>` | Calls `POST /api/auth/login` |
| `register(data)` | `Promise<void>` | Calls `POST /api/auth/register` |
| `logout()` | `void` | Clears localStorage and state |
| `updateProfile(data)` | `Promise<void>` | Calls `PATCH /api/auth/profile` |
| `saveWalletAddress(addr)` | `Promise<void>` | Calls `PATCH /api/auth/profile` with `walletAddress` |

### User object shape (VashudhaUser)

The `_normalizeUser` function in `useAuth.tsx` maps backend snake_case to camelCase:

```ts
// Donor
{
  id, role: "donor", email, phone, name, address, city, state, pincode,
  verified, createdAt, walletAddress?,
  donorType, businessName, gstNumber?, fssaiLicense?
}

// NGO
{
  id, role: "ngo", email, phone, name, address, city, state, pincode,
  verified, createdAt, walletAddress?,
  ngoName, darpanId?, registrationNumber?, panNumber?, operatingAreas[]
}

// Corporate
{
  id, role: "corporate", email, phone, name, address, city, state, pincode,
  verified, createdAt, walletAddress?,
  companyName, gstNumber, designation, cin?, companyPan?, companyWebsite?
}
```

### Protecting pages

```tsx
"use client";
import { useAuth } from "@/hooks/useAuth";
import { useRouter } from "next/navigation";
import { useEffect } from "react";

export default function ProtectedPage() {
  const { isAuthenticated, isLoading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!isLoading && !isAuthenticated) router.push("/auth/login");
  }, [isAuthenticated, isLoading]);

  if (isLoading) return <div>Loading...</div>;
  return <div>Protected content</div>;
}
```

---

## Error Reference

All error responses follow this shape:
```json
{ "error": "Human-readable error message" }
```

| HTTP Status | Meaning |
|---|---|
| `400 Bad Request` | Missing/invalid fields in request body |
| `401 Unauthorized` | Missing token, expired token, wrong password |
| `403 Forbidden` | Wrong role (e.g. non-donor on donor-only route) |
| `404 Not Found` | User/resource not found |
| `409 Conflict` | Email already registered |
| `422 Unprocessable` | Semantic error (e.g. insufficient balance) |
| `500 Internal Error` | Database failure |

---

## Environment Variables

### Backend (`vashudha-backend/.env`)
```env
# Required for auth
JWT_SECRET=vashudha-super-secret-jwt-key-change-in-production
JWT_EXPIRY_HOURS=72

# Required for DB
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_KEY=your-service-role-key

# Admin routes
ADMIN_SECRET=harvestmind-admin-secret
```

### Frontend (`vashudha/.env.local`)
```env
NEXT_PUBLIC_API_URL=http://localhost:5000
```

> ⚠️ **Never commit real secrets.** Both `.env` and `.env.local` are gitignored.
