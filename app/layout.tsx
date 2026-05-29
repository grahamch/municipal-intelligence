import type { Metadata } from "next"
import { Geist, Geist_Mono } from "next/font/google"
import "./globals.css"
import Link from "next/link"

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
})

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
})

export const metadata: Metadata = {
  title: "Municipal Billing Intelligence",
  description: "Detecting billing errors across South African municipalities",
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">
        <nav className="bg-white border-b border-gray-200 px-8 py-4">
          <div className="max-w-4xl mx-auto flex items-center justify-between">
            <span className="font-bold text-gray-900">Municipal Intelligence</span>
            <div className="flex gap-6">
              <Link href="/" className="text-sm text-gray-600 hover:text-gray-900">Dashboard</Link>
              <Link href="/bills" className="text-sm text-gray-600 hover:text-gray-900">Bills</Link>
            </div>
          </div>
        </nav>
        {children}
      </body>
    </html>
  )
}