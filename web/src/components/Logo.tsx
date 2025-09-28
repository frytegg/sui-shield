import logoImage from 'figma:asset/810d55331385e4f36caa5586d559293b59fec87b.png';

interface LogoProps {
  size?: 'sm' | 'md' | 'lg';
  showText?: boolean;
  className?: string;
}

export function Logo({ size = 'md', showText = true, className = '' }: LogoProps) {
  const sizeClasses = {
    sm: {
      logo: 'w-6 h-6',
      text: 'text-sm',
    },
    md: {
      logo: 'w-8 h-8',
      text: 'text-lg',
    },
    lg: {
      logo: 'w-12 h-12',
      text: 'text-2xl',
    },
  };

  const classes = sizeClasses[size];

  return (
    <div className={`flex items-center space-x-3 ${className}`}>
      <div className="relative">
        <img 
          src={logoImage} 
          alt="Mist Limit Logo" 
          className={`${classes.logo} object-contain`}
        />
      </div>
      
      {showText && (
        <div className="flex flex-col">
          <span className={`font-bold ${classes.text} text-foreground tracking-tight leading-none`}>
            Mist Limit
          </span>
        </div>
      )}
    </div>
  );
}