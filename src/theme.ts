import { useColorScheme } from 'react-native';

export const spacing = { xs: 4, sm: 8, md: 16, lg: 24, xl: 32 } as const;

export const fontSize = {
  title: 28,
  heading: 20,
  body: 16,
  label: 14,
  caption: 12,
} as const;

/** Minimum tappable size in pt. Every touchable in the app sets at least this. */
export const touchTarget = 44;

export const radius = 12;

const light = {
  background: '#FFFFFF',
  surface: '#F4F4F7',
  border: '#DEDEE4',
  text: '#141419',
  textMuted: '#5C5C68',
  accent: '#E0518A',
  accentText: '#FFFFFF',
  success: '#1E7F52',
  warning: '#9A6300',
  danger: '#B3261E',
};

const dark: typeof light = {
  background: '#121215',
  surface: '#1E1E23',
  border: '#33333B',
  text: '#F2F2F5',
  textMuted: '#A5A5B0',
  accent: '#FF7FAE',
  accentText: '#1A0A11',
  success: '#5FD39B',
  warning: '#E0B252',
  danger: '#F2A9A3',
};

export type Colors = typeof light;

export const colors = { light, dark };

export function useColors(): Colors {
  return useColorScheme() === 'dark' ? dark : light;
}
