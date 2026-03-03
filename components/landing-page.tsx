'use client'

import { Button } from '@/components/ui/button'
import { ChevronRight20Regular } from '@fluentui/react-icons'
import { useRouter } from 'next/navigation'
import { motion } from 'framer-motion'
import Image from 'next/image'

export function LandingPage() {
  const router = useRouter()

  return (
    <div className="min-h-screen flex flex-col items-center justify-center px-4 relative">
      {/* Centered Content */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5, ease: [0.25, 0.46, 0.45, 0.94] }}
        className="text-center max-w-2xl"
      >
        {/* Logo Icon */}
        <div className="mb-8 inline-flex w-20 h-20 rounded-2xl bg-accent-subtle items-center justify-center">
          <Image
            src="/icons/ai-foundry.png"
            alt="Microsoft Foundry IQ"
            width={48}
            height={48}
            className="opacity-80"
          />
        </div>

        {/* Title */}
        <h1 className="text-5xl md:text-6xl font-bold text-fg-default tracking-tight mb-4">
          Microsoft Foundry IQ
        </h1>

        {/* Tagline */}
        <p className="text-xl text-fg-muted mb-10">
          Intelligent knowledge retrieval for enterprise agents
        </p>

        {/* CTA Button */}
        <Button
          size="lg"
          className="h-14 px-10 text-lg bg-accent hover:bg-accent-hover text-fg-on-accent"
          onClick={() => router.push('/test')}
        >
          Try Demo
          <ChevronRight20Regular className="ml-2 h-5 w-5" />
        </Button>
      </motion.div>

      {/* Minimal Footer */}
      <footer className="absolute bottom-0 left-0 right-0 p-6 text-center text-sm text-fg-muted">
        Azure AI Search Product Group
      </footer>
    </div>
  )
}
