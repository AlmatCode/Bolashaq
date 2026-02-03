import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { fullName, email, group, speciality, iin, category, phone, dateOfBirth } = await req.json()

    // Инициализация Supabase с сервисной ролью
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    )

    // Генерация username из ФИО
    const username = generateUsername(fullName)
    const password = generateSixDigitPassword()

    // Создание auth пользователя
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        role: 'student',
      },
    })

    if (authError) throw authError

    // Создание профиля
    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .insert({
        id: authData.user.id,
        full_name: fullName,
        email,
        username,
        role: 'student',
        student_group: group,
        student_speciality: speciality,
        iin,
        category,
        phone,
        date_of_birth: dateOfBirth,
        verified_for_food: false,
        balance: 0.00,
      })

    if (profileError) throw profileError

    return new Response(
      JSON.stringify({
        success: true,
        userId: authData.user.id,
        username,
        password
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      },
    )
  }
})

function generateUsername(fullName: string): string {
  // Логика генерации username из ФИО
  const translitMap: Record<string, string> = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ы': 'y', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  }

  let transliterated = fullName.toLowerCase()
  Object.entries(translitMap).forEach(([cyr, lat]) => {
    transliterated = transliterated.replaceAll(cyr, lat)
  })

  transliterated = transliterated.replaceAll(/[^a-z\s]/g, '')
  const words = transliterated.trim().split(/\s+/)

  if (words.length >= 2) {
    const firstName = words[0]
    const lastName = words[words.length - 1]
    return `${capitalize(firstName)}_${capitalize(lastName)}`
  }

  return words[0] ? capitalize(words[0]) : 'Student'
}

function capitalize(word: string): string {
  return word.charAt(0).toUpperCase() + word.slice(1)
}

function generateSixDigitPassword(): string {
  return Math.floor(100000 + Math.random() * 900000).toString()
}